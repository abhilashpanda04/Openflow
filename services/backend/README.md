# ASR Backend

Backend for the speech-to-text desktop application, powered by FastAPI and NeMo/Olmo ASR services.

## Repository layout
- `backend/app.py`: FastAPI app that wires request handling, model loading, and transcription pipelines.
- `backend/test_*.py`: Standalone scripts covering sanity checks across the ASR stack (they are not part of a pytest suite).

## Setup
1. (Optional) create and activate a virtual environment.
2. Install the base dependencies (FastAPI, Uvicorn, Torch, Qwen ASR) which are sufficient for the Qwen server:
   ```bash
   uv sync
   # or
   python3 -m venv .venv
   ./.venv/bin/pip install -e .
   ```
3. If you also need the NeMo-based backend (`app.py` and the streaming endpoints), install the extra requirements:
   ```bash
   ./.venv/bin/pip install -e ".[backend]"
   ```

## Running the API
- `./.venv/bin/python app.py` (the module starts `uvicorn` automatically).
- Equivalent: `./.venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port 8000`.
- Health check: `curl http://127.0.0.1:8000/health`.
- Root path now responds with a small status payload: `curl http://127.0.0.1:8000/`.

## Security Configuration
Both `app.py` and `qwen_server.py` support optional authentication and security hardening via environment variables:
- **`ASR_LOCAL_API_TOKEN`**: if set, clients must send a matching `X-API-Token` header. Recommended for production use.
- **`BACKEND_ALLOWED_ORIGINS`** (app.py only): comma-separated list of allowed CORS origins (default: `http://127.0.0.1:3000,http://localhost:3000`). Set to `*` to allow all origins (not recommended for production).
- **`QWEN_MAX_UPLOAD_BYTES`** (qwen_server.py): maximum upload size in bytes (default: 26214400 = ~25MB).

Example:
```bash
export ASR_LOCAL_API_TOKEN="your-secret-token-here"
export BACKEND_ALLOWED_ORIGINS="http://127.0.0.1:3000,http://localhost:8080"
./.venv/bin/python app.py
```

On the client side (e.g., Swift/macOS), configure the token in settings and the client will include it in the `X-API-Token` header for all requests.

## Quick checks
```bash
./.venv/bin/python -m compileall .
```

## Tests
Run each standalone script when needed (they can load large models):
```bash
./.venv/bin/python test_nemo.py
./.venv/bin/python test_direct.py
./.venv/bin/python test_decode.py
./.venv/bin/python test_upload.py
./.venv/bin/python test_official.py
```

## Qwen ASR server
- The optional `qwen_server.py` spins up a FastAPI service that loads `Qwen/Qwen3-ASR-1.7B` via `qwen_asr.Qwen3ASRModel` on `localhost:8001`.
- Because the base dependency set already installs FastAPI, Uvicorn, Torch, and `qwen-asr`, no additional packages are required to run this server.
- Optional hardening env vars:
  - `ASR_LOCAL_API_TOKEN`: if set, clients must send matching `X-API-Token` header.
  - `QWEN_MAX_UPLOAD_BYTES`: max accepted upload size in bytes (default `26214400`).
  - `X-Request-ID`: optional request correlation header (server echoes it back).
- To run it:
  ```bash
  cd backend
  uv run python qwen_server.py
  ```
  The command delegates to `uvicorn qwen_server:app` and serves `/transcribe` + `/health` for macOS clients.
- The root path (`/`) now replies with a minimal JSON payload so hitting `http://127.0.0.1:8001/` no longer returns 404.

## Notes
- No linting/formatting/typecheck tools are configured in `pyproject.toml` yet.
- Keep response keys (`success`, `text`, `language`, `error`) stable; they are consumed by the Electron frontend.

## Smoke test
With server running locally:
```bash
./.venv/bin/python test_smoke_local.py
```
