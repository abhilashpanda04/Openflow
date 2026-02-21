"""Local Qwen ASR server for macOS clients."""

from __future__ import annotations

import asyncio
import io
import logging
import os
import tempfile
import uuid
import wave
from pathlib import Path
from typing import Any

import torch
from fastapi import FastAPI, File, Form, Header, HTTPException, Request, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from qwen_asr import Qwen3ASRModel


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("qwen_server")

app = FastAPI(title="Qwen ASR Local Server", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

MODEL_NAME = os.getenv("OPENFLOW_MODEL_NAME", "Qwen/Qwen3-ASR-0.6B")
MAX_NEW_TOKENS = 256
MAX_BATCH_SIZE = 8
MAX_UPLOAD_BYTES = int(os.getenv("QWEN_MAX_UPLOAD_BYTES", str(25 * 1024 * 1024)))
MIN_UPLOAD_BYTES = int(os.getenv("QWEN_MIN_UPLOAD_BYTES", "96"))
LOCAL_API_TOKEN = os.getenv("ASR_LOCAL_API_TOKEN", "").strip() or None
ALLOWED_AUDIO_EXTENSIONS = {".wav", ".mp3", ".flac", ".ogg", ".m4a", ".webm"}
REQUEST_ID_HEADER = "X-Request-ID"


def _select_device_and_dtype() -> tuple[str, torch.dtype]:
    """Pick a macOS-safe device and dtype."""
    if torch.backends.mps.is_available():
        return "mps", torch.float16
    return "cpu", torch.float32


def _extract_result_fields(result_item: Any) -> tuple[str, str]:
    """Extract language and text from model output item."""
    language = getattr(result_item, "language", "unknown")
    text = getattr(result_item, "text", "")

    if text is None:
        text = ""

    if not isinstance(text, str):
        text = str(text)

    if text.strip() == "":
        # Avoid leaking object reprs like
        # ASRTranscription(language='', text='', time_stamps=None)
        if isinstance(result_item, str):
            text = result_item
        else:
            text = ""

    if language is None or str(language).strip() == "":
        language = "unknown"

    return language, text


def _validate_local_token(x_api_token: str | None) -> None:
    if LOCAL_API_TOKEN is None:
        return
    if x_api_token != LOCAL_API_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid or missing API token")


def _resolve_request_id(incoming_request_id: str | None) -> str:
    candidate = (incoming_request_id or "").strip()
    if candidate:
        return candidate
    return uuid.uuid4().hex


def _looks_empty_audio(payload: bytes, suffix: str) -> bool:
    if len(payload) < MIN_UPLOAD_BYTES:
        return True

    if suffix == ".wav":
        try:
            with wave.open(io.BytesIO(payload), "rb") as wav_file:
                return wav_file.getnframes() <= 0
        except Exception:
            return False

    return False


DEVICE_MAP, DTYPE = _select_device_and_dtype()

try:
    logger.info("Loading %s on device=%s dtype=%s", MODEL_NAME, DEVICE_MAP, DTYPE)
    model = Qwen3ASRModel.from_pretrained(
        MODEL_NAME,
        dtype=DTYPE,
        device_map=DEVICE_MAP,
        max_inference_batch_size=MAX_BATCH_SIZE,
        max_new_tokens=MAX_NEW_TOKENS,
    )
    model_load_error = None
    logger.info("Model loaded successfully")
except Exception as exc:  # pragma: no cover - runtime environment dependent
    model = None
    model_load_error = str(exc)
    logger.exception("Failed to load model: %s", exc)


@app.get("/health")
async def health(
    response: Response,
    x_api_token: str | None = Header(default=None),
    x_request_id: str | None = Header(default=None),
) -> dict[str, Any]:
    _validate_local_token(x_api_token)
    request_id = _resolve_request_id(x_request_id)
    response.headers[REQUEST_ID_HEADER] = request_id
    payload = {
        "status": "healthy" if model is not None else "degraded",
        "model_loaded": model is not None,
        "model_name": MODEL_NAME,
        "device": DEVICE_MAP,
        "dtype": str(DTYPE),
        "max_upload_bytes": MAX_UPLOAD_BYTES,
        "auth_enabled": LOCAL_API_TOKEN is not None,
        "error": model_load_error,
        "request_id": request_id,
    }
    logger.info("health request_id=%s status=%s", request_id, payload["status"])
    return payload


@app.get("/")
async def root(
    response: Response,
    x_api_token: str | None = Header(default=None),
    x_request_id: str | None = Header(default=None),
) -> dict[str, Any]:
    _validate_local_token(x_api_token)
    request_id = _resolve_request_id(x_request_id)
    response.headers[REQUEST_ID_HEADER] = request_id
    payload = {
        "status": "ok",
        "message": "Qwen ASR backend is running.",
        "model_loaded": model is not None,
        "auth_enabled": LOCAL_API_TOKEN is not None,
        "request_id": request_id,
        "available_endpoints": ["/health", "/transcribe"],
    }
    logger.info("root request_id=%s", request_id)
    return payload


@app.post("/transcribe")
async def transcribe(
    response: Response,
    request: Request,
    audio: UploadFile = File(...),
    language: str | None = Form(default=None),
    x_api_token: str | None = Header(default=None),
    x_request_id: str | None = Header(default=None),
) -> Any:
    request_id = _resolve_request_id(x_request_id)
    response.headers[REQUEST_ID_HEADER] = request_id

    _validate_local_token(x_api_token)

    if request.client and request.client.host not in {"127.0.0.1", "::1", "localhost"}:
        logger.warning("Rejected non-loopback request request_id=%s host=%s", request_id, request.client.host)
        return JSONResponse({"error": "Only loopback requests are allowed", "request_id": request_id}, status_code=403)

    if model is None:
        return JSONResponse(
            {"error": f"Model failed to load: {model_load_error}", "request_id": request_id},
            status_code=503,
        )

    if not audio.filename:
        return JSONResponse({"error": "No file selected", "request_id": request_id}, status_code=400)

    suffix = Path(audio.filename).suffix.lower() or ".wav"
    if suffix not in ALLOWED_AUDIO_EXTENSIONS:
        return JSONResponse(
            {
                "error": (
                    "Unsupported audio extension. "
                    f"Allowed: {', '.join(sorted(ALLOWED_AUDIO_EXTENSIONS))}"
                ),
                "request_id": request_id,
            },
            status_code=400,
        )

    payload = await audio.read()
    if not payload:
        return JSONResponse({"error": "Uploaded file is empty", "request_id": request_id}, status_code=400)

    if len(payload) > MAX_UPLOAD_BYTES:
        return JSONResponse(
            {
                "error": (
                    "File exceeds upload limit "
                    f"({len(payload)} bytes > {MAX_UPLOAD_BYTES} bytes)"
                ),
                "request_id": request_id,
            },
            status_code=413,
        )

    if _looks_empty_audio(payload, suffix):
        logger.info("Skipping empty audio request_id=%s size=%s", request_id, len(payload))
        return {
            "success": True,
            "language": "unknown",
            "text": "",
            "request_id": request_id,
        }

    temp_path = ""

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            temp_path = temp_file.name
            temp_file.write(payload)

        def _run_transcription() -> list[Any]:
            return model.transcribe(audio=temp_path, language=language)

        results = await asyncio.to_thread(_run_transcription)
        if not results:
            return {"success": True, "language": "unknown", "text": "", "request_id": request_id}

        result_language, result_text = _extract_result_fields(results[0])
        return {
            "success": True,
            "language": result_language,
            "text": result_text.strip(),
            "request_id": request_id,
        }

    except Exception as exc:
        error_text = str(exc)
        if "[1, 1, 0]" in error_text or "non-zero dimensions for input" in error_text:
            logger.warning("Empty tensor from model request_id=%s; returning empty text", request_id)
            return {
                "success": True,
                "language": "unknown",
                "text": "",
                "request_id": request_id,
            }

        logger.exception("Transcription failed request_id=%s: %s", request_id, exc)
        return JSONResponse(
            {"error": f"Transcription failed: {exc}", "request_id": request_id},
            status_code=500,
        )
    finally:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8001, reload=False)
