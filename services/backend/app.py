"""
Speech-to-Text Application Backend
Uses Faster Whisper for automatic speech recognition
"""

import os
import logging
from pathlib import Path
import sys
import shutil
from typing import Optional

from fastapi import FastAPI, UploadFile, File, HTTPException, Request, BackgroundTasks, WebSocket, WebSocketDisconnect, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.concurrency import run_in_threadpool
import numpy as np
from dotenv import load_dotenv
import nemo.collections.asr as nemo_asr
import asyncio
import io
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
import multiprocessing

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(title="ASR Backend")

# Authentication configuration
LOCAL_API_TOKEN = os.getenv("ASR_LOCAL_API_TOKEN", "").strip() or None

# CORS Configuration - allow configurable origins for security
ALLOWED_ORIGINS = os.getenv("BACKEND_ALLOWED_ORIGINS", "").strip()
if ALLOWED_ORIGINS:
    allow_origins = [origin.strip() for origin in ALLOWED_ORIGINS.split(",") if origin.strip()]
else:
    # Default: only allow loopback for desktop use
    allow_origins = ["http://127.0.0.1:3000", "http://localhost:3000"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration
UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'wav', 'mp3', 'flac', 'ogg'}
MAX_FILE_SIZE = 100 * 1024 * 1024  # 100MB
SAMPLE_RATE = 16000

# Create upload folder if it doesn't exist
Path(UPLOAD_FOLDER).mkdir(exist_ok=True)


def detect_device():
    """Detect the best available device for model inference"""
    import torch
    
    # Check for MPS (Apple Silicon GPU)
    if torch.backends.mps.is_available():
        logger.info("M-series chip detected - using MPS (Metal Performance Shaders) for GPU acceleration")
        return "mps"
    
    # Check for CUDA (NVIDIA GPU)
    if torch.cuda.is_available():
        logger.info("CUDA-capable GPU detected")
        return "cuda"
    
    # Fallback to CPU
    logger.info("No GPU acceleration available - using CPU")
    return "cpu"


# Initialize the speech-to-text model
try:
    device = detect_device()
    logger.info(f"Loading NeMo Parakeet TDT 0.6B v2 model on {device}...")
    
    # Use NeMo ASR model (handles device placement automatically)
    asr_model = nemo_asr.models.ASRModel.from_pretrained(
        model_name="nvidia/parakeet-tdt-0.6b-v2"
    )
    
    logger.info(f"Model loaded successfully")
except Exception as e:
    logger.error(f"Failed to load model: {str(e)}")
    asr_model = None
    device = "unknown"

# Create thread pool for parallel transcription
# Faster Whisper can handle multiple concurrent requests
MAX_WORKERS = min(4, multiprocessing.cpu_count())  # Use up to 4 parallel workers
executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)
logger.info(f"Created thread pool with {MAX_WORKERS} workers for parallel processing")

# Inference concurrency control - limit concurrent model calls to prevent resource exhaustion
# Most ASR models (especially GPU-based) are not thread-safe for concurrent inference
inference_semaphore = asyncio.Semaphore(1)  # Allow only 1 concurrent inference


def validate_local_token(x_api_token: str | None = Header(default=None)) -> None:
    """Validate API token if configured via ASR_LOCAL_API_TOKEN environment variable."""
    if LOCAL_API_TOKEN is None:
        return
    if x_api_token != LOCAL_API_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid or missing API token")


def allowed_file(filename: str) -> bool:
    """Check if file extension is allowed"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


@app.get("/health")
def health_check(_auth: None = Depends(validate_local_token)):
    """Health check endpoint"""
    return {
        'status': 'healthy',
        'model_loaded': asr_model is not None,
        'model_type': 'NeMo Parakeet TDT 0.6B v2',
        'device': device if asr_model is not None else 'unknown',
        'auth_enabled': LOCAL_API_TOKEN is not None
    }


@app.get("/")
def root() -> dict[str, object]:
    """Basic service info to prevent root-level 404s."""
    return {
        'status': 'ok',
        'message': 'ASR backend is running.',
        'model_loaded': asr_model is not None,
        'available_endpoints': ['/health', '/transcribe', '/transcribe-stream', '/ws/transcribe']
    }


@app.post("/transcribe")
async def transcribe_audio(
    audio: UploadFile = File(...),
    _auth: None = Depends(validate_local_token)
):
    """
    Transcribe audio file to text
    Expects: multipart/form-data with 'audio' file
    Returns: JSON with transcription text
    """
    try:
        # Validate model is loaded
        if asr_model is None:
            return JSONResponse({
                'error': 'Model not loaded. Please restart the application.'
            }, status_code=503)

        # Validate filename
        if not audio.filename:
            return JSONResponse({'error': 'No file selected'}, status_code=400)

        if not allowed_file(audio.filename):
            return JSONResponse({
                'error': f'File type not allowed. Allowed types: {", ".join(ALLOWED_EXTENSIONS)}'
            }, status_code=400)

        # Save uploaded file with unique name to prevent race conditions
        import time
        import random
        import string
        timestamp = int(time.time() * 1000)
        random_suffix = ''.join(random.choices(string.ascii_lowercase, k=6))
        unique_filename = f"{timestamp}_{random_suffix}_{audio.filename}"
        file_path = os.path.join(UPLOAD_FOLDER, unique_filename)
        
        try:
            # Write file to disk
            with open(file_path, "wb") as buffer:
                shutil.copyfileobj(audio.file, buffer)
            
            # Check file size
            file_size = os.path.getsize(file_path)
            if file_size > MAX_FILE_SIZE:
                os.remove(file_path)
                return JSONResponse({'error': f'File size exceeds {MAX_FILE_SIZE / (1024 * 1024):.0f}MB limit'}, status_code=413)
            
            # Skip chunks that are too small (likely incomplete/corrupted)
            MIN_CHUNK_SIZE = 5000  # 5KB minimum - smaller chunks are often incomplete WebM
            if file_size < MIN_CHUNK_SIZE:
                logger.warning(f"Skipping small chunk ({file_size} bytes)")
                os.remove(file_path)
                return {
                    'success': True,
                    'text': '',  # Empty result for invalid chunk
                    'language': 'unknown',
                    'filename': audio.filename
                }


            logger.info(f"Processing audio file: {audio.filename}")

            # Load and process audio - running in threadpool to avoid blocking
            import time
            request_id = f"{audio.filename}_{int(time.time()*1000) % 10000}"
            logger.info(f"[{request_id}] Starting transcription (parallel processing enabled)...")
            
            # Define a helper for the blocking call
            def run_transcription(path):
                # Convert WebM to WAV if needed (MediaRecorder creates WebM)
                from pydub import AudioSegment
                
                try:
                    # Validate file can be read before processing
                    try:
                        with open(path, 'rb') as f:
                            # Read first few bytes to check if file is valid
                            header = f.read(100)
                            if len(header) < 100:
                                logger.warning(f"File too small or incomplete: {len(header)} bytes")
                                return "", None
                    except Exception as e:
                        logger.warning(f"Cannot read file: {str(e)}")
                        return "", None
                    
                    # Try to load as any format pydub supports
                    audio_data = AudioSegment.from_file(path)
                    
                    # Convert to mono and set sample rate for NeMo
                    audio_data = audio_data.set_channels(1).set_frame_rate(16000)
                    
                    # Convert to WAV for NeMo
                    wav_path = path.rsplit('.', 1)[0] + '.wav'
                    audio_data.export(wav_path, format='wav')
                    
                    # Transcribe using NeMo (handles long audio efficiently)
                    result = asr_model.transcribe([wav_path])[0]
                    # Extract text from Hypothesis object
                    transcription = result.text if hasattr(result, 'text') else str(result)
                    
                    # Clean up temporary WAV
                    if wav_path != path:
                        os.remove(wav_path)
                    
                    # Create compatible info object
                    from collections import namedtuple
                    Info = namedtuple('Info', ['language', 'language_probability'])
                    info = Info(language='en', language_probability=0.99)
                    
                    return transcription, info
                except Exception as e:
                    logger.error(f"Audio conversion/transcription error: {str(e)}")
                    return "", None

            # Limit concurrent inference to prevent resource exhaustion
            async with inference_semaphore:
                transcription, info = await run_in_threadpool(run_transcription, file_path)
            
            # Handle invalid/empty chunks
            if info is None or transcription == "":
                logger.info("Chunk was invalid or empty, returning empty result")
                os.remove(file_path)
                return {
                    'success': True,
                    'text': '',
                    'language': 'unknown',
                    'filename': audio.filename
                }
            
            logger.info(f"[{request_id}] Transcription completed. Language: {info.language}, Prob: {info.language_probability}")

            # Clean up uploaded file
            os.remove(file_path)

            return {
                'success': True,
                'text': transcription.strip(),
                'language': info.language,
                'filename': audio.filename
            }

        except Exception as e:
            logger.error(f"Error during transcription: {str(e)}")
            # Clean up on error
            if os.path.exists(file_path):
                os.remove(file_path)
            
            # For chunk processing, return empty result instead of error
            # This allows streaming to continue even if one chunk fails
            return {
                'success': True,
                'text': '',
                'language': 'unknown',
                'filename': audio.filename
            }

    except Exception as e:
        logger.error(f"Unexpected error in /transcribe: {str(e)}")
        return JSONResponse({'error': 'Internal server error'}, status_code=500)


@app.post("/transcribe-stream")
async def transcribe_stream(
    request: Request,
    _auth: None = Depends(validate_local_token)
):
    """
    Transcribe audio stream in real-time
    Expects: application/octet-stream with raw audio data
    Returns: JSON with transcription text
    """
    try:
        if asr_model is None:
            return JSONResponse({
                'error': 'Model not loaded. Please restart the application.'
            }, status_code=503)

        # Check content length before reading body to prevent DoS
        content_length = request.headers.get("content-length")
        if content_length and int(content_length) > MAX_FILE_SIZE:
            return JSONResponse({'error': f'Payload too large (max {MAX_FILE_SIZE} bytes)'}, status_code=413)

        # Get audio data from request body
        audio_data = await request.body()

        if not audio_data:
            return JSONResponse({'error': 'No audio data provided'}, status_code=400)

        # Processing logic
        try:
            # Define helper for cpu intensive work
            def process_stream(data):
                # Convert bytes to numpy array
                audio_array = np.frombuffer(data, dtype=np.float32)

                # Normalize if needed
                if np.max(np.abs(audio_array)) > 1.0:
                    audio_array = audio_array / np.max(np.abs(audio_array))

                logger.info(f"Processing streamed audio ({len(audio_array)} samples)")

                # Save temporarily for Whisper (requires file path or binary stream)
                import soundfile as sf
                temp_file = os.path.join(UPLOAD_FOLDER, 'stream_temp.wav')
                sf.write(temp_file, audio_array, SAMPLE_RATE)
                
                try:
                    result = asr_model.transcribe([temp_file])[0]
                    text = result.text if hasattr(result, 'text') else str(result)
                finally:
                    if os.path.exists(temp_file):
                        os.remove(temp_file)
                
                return text

            # Limit concurrent inference to prevent resource exhaustion
            async with inference_semaphore:
                transcription = await run_in_threadpool(process_stream, audio_data)

            logger.info(f"Stream transcription completed: {transcription[:100]}...")

            return {
                'success': True,
                'text': transcription.strip()
            }

        except Exception as e:
            logger.error(f"Error processing audio stream: {str(e)}")
            return JSONResponse({'error': f'Stream processing failed: {str(e)}'}, status_code=500)

    except Exception as e:
        logger.error(f"Unexpected error in /transcribe-stream: {str(e)}")
        return JSONResponse({'error': 'Internal server error'}, status_code=500)



@app.websocket("/ws/transcribe")
async def websocket_transcribe(websocket: WebSocket):
    """
    WebSocket endpoint for real-time transcription streaming
    Client sends audio chunks, server returns transcriptions
    """
    # Validate token before accepting connection
    token = dict(websocket.headers).get("x-api-token")
    if LOCAL_API_TOKEN and token != LOCAL_API_TOKEN:
        await websocket.close(code=1008, reason="Invalid or missing API token")
        logger.warning("WebSocket connection rejected: invalid token")
        return
    
    await websocket.accept()
    logger.info("WebSocket connection established")
    
    audio_buffer = bytearray()
    BUFFER_SIZE = 128000  # ~8 seconds of audio - larger buffer for complete WebM segments
    MIN_VALID_SIZE = 50000  # Minimum 50KB for valid WebM data
    MAX_BUFFER_SIZE = 10 * 1024 * 1024  # 10MB absolute maximum to prevent memory exhaustion
    
    try:
        while True:
            # Receive audio data from client
            data = await websocket.receive_bytes()
            audio_buffer.extend(data)
            
            # Enforce maximum buffer size to prevent DoS
            if len(audio_buffer) > MAX_BUFFER_SIZE:
                logger.warning(f"Buffer exceeded maximum size ({len(audio_buffer)} bytes), closing connection")
                await websocket.close(code=1009, reason="Message too large")
                return
            
            # Process buffer when it reaches threshold
            if len(audio_buffer) >= BUFFER_SIZE:
                logger.info(f"Processing audio buffer ({len(audio_buffer)} bytes)")
                
                # Skip if buffer is too small to be valid
                if len(audio_buffer) < MIN_VALID_SIZE:
                    logger.warning(f"Buffer too small, skipping ({len(audio_buffer)} bytes)")
                    audio_buffer.clear()
                    continue
                
                # Process in thread pool to avoid blocking
                def process_buffer(buffer_data):
                    try:
                        from pydub import AudioSegment
                        import tempfile
                        
                        # Validate WebM header (should start with EBML marker: 0x1A 0x45 0xDF 0xA3)
                        if len(buffer_data) < 4 or buffer_data[0:4] != b'\x1a\x45\xdf\xa3':
                            logger.warning("Invalid WebM header, skipping buffer")
                            return "", "error"
                        
                        # Create temporary file for audio processing
                        with tempfile.NamedTemporaryFile(suffix='.webm', delete=False) as temp_file:
                            temp_file.write(buffer_data)
                            temp_path = temp_file.name
                        
                        try:
                            # Convert to WAV
                            audio = AudioSegment.from_file(temp_path)
                            wav_path = temp_path.replace('.webm', '.wav')
                            audio.export(wav_path, format='wav')
                            
                            # Transcribe using NeMo
                            result = asr_model.transcribe([wav_path])[0]
                            text = result.text if hasattr(result, 'text') else str(result)
                            
                            # Cleanup
                            os.remove(temp_path)
                            os.remove(wav_path)
                            
                            return text.strip(), 'en'
                        except Exception as e:
                            logger.error(f"Buffer processing error: {str(e)}")
                            if os.path.exists(temp_path):
                                os.remove(temp_path)
                            return "", "error"
                    except Exception as e:
                        logger.error(f"Buffer conversion error: {str(e)}")
                        return "", "error"
                
                # Run transcription in thread pool with concurrency control
                async with inference_semaphore:
                    text, language = await run_in_threadpool(process_buffer, bytes(audio_buffer))
                
                # Send result back to client
                if text:
                    await websocket.send_json({
                        'type': 'transcription',
                        'text': text,
                        'language': language,
                        'is_final': False
                    })
                    logger.info(f"Sent transcription: {text[:50]}...")
                
                # Clear processed buffer
                audio_buffer.clear()
                
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {str(e)}")
        try:
            await websocket.close()
        except:
            pass


if __name__ == '__main__':
    import uvicorn
    debug_mode = os.environ.get('FLASK_DEBUG', 'false').lower() == 'true'
    port = int(os.environ.get('PORT', 8000))
    # Note: reload=debug_mode might not work programmatically efficiently, usually better to run via CLI
    uvicorn.run("app:app", host="0.0.0.0", port=port, reload=debug_mode)
