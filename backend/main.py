"""Local-only API orchestrating the stable model adapters."""
import logging
import tempfile
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

from backend.config import ASR_DIR, AUDIO_DIR, LANGUAGES, MODE, VOICES, VOICES_DIR
from backend.models.asr import ModelUnavailable, speech_to_text
from backend.models.translation import translate_and_extract
from backend.models.tts import text_to_speech
from backend.schemas import ProcessResult

logger = logging.getLogger("fieldtalk")
app = FastAPI(title="FieldTalk local API")
MAX_AUDIO_BYTES = 10 * 1024 * 1024
ALLOWED_SUFFIXES = {".webm", ".wav", ".ogg", ".mp4", ".m4a"}


@app.get("/health")
def health():
    if MODE == "mock":
        return {"mode": MODE, "ready": True, "components": {"asr": "mock", "translation": "mock", "tts": "mock"}}
    try:
        from argostranslate import package
        installed = {(p.from_code, p.to_code) for p in package.get_installed_packages()}
    except ImportError:
        installed = set()
    components = {
        "asr": "ready" if (ASR_DIR / "model.bin").is_file() else "missing",
        "translation": (
            "ready" if SUPPORTED_PAIRS <= installed else "missing"
        ),
        "tts": "ready" if all(
            (VOICES_DIR / f"{name}.onnx").is_file() and (VOICES_DIR / f"{name}.onnx.json").is_file()
            for name in VOICES.values()
        ) else "missing",
    }
    return {"mode": MODE, "ready": all(v == "ready" for v in components.values()), "components": components}


@app.post("/process_audio", response_model=ProcessResult)
async def process_audio(
    audio: UploadFile = File(...),
    source_language: str = Form(...),
    target_language: str = Form(...),
):
    if (source_language, target_language) not in SUPPORTED_PAIRS:
        raise HTTPException(
            400,
            "Supported pairs: English ↔ Chinese and English ↔ Russian.",
        )
    suffix = Path(audio.filename or "").suffix.lower()
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(400, "Unsupported audio format. Record WebM or upload WAV, OGG, MP4, or M4A.")
    data = await audio.read(MAX_AUDIO_BYTES + 1)
    if not data:
        raise HTTPException(400, "No audio recorded. Please record again.")
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(413, "Audio is too large. Keep recordings under 10 MB.")
    started = time.perf_counter()
    timings = {}
    with tempfile.TemporaryDirectory(prefix="fieldtalk-") as folder:
        input_path = Path(folder) / f"input{suffix}"
        input_path.write_bytes(data)
        try:
            t0 = time.perf_counter()
            recognized = speech_to_text(input_path, source_language)
            timings["asr"] = round((time.perf_counter() - t0) * 1000, 1)
            t0 = time.perf_counter()
            translated = translate_and_extract(recognized.text, source_language, target_language)
            timings["translation"] = round((time.perf_counter() - t0) * 1000, 1)
            t0 = time.perf_counter()
            output_path = text_to_speech(translated.translation, target_language)
            timings["tts"] = round((time.perf_counter() - t0) * 1000, 1)
        except ModelUnavailable as exc:
            raise HTTPException(503, str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        except RuntimeError as exc:
            logger.exception("Pipeline failed")
            raise HTTPException(500, str(exc)) from exc
    timings["total"] = round((time.perf_counter() - started) * 1000, 1)
    logger.info("Pipeline timing (ms): %s", timings)
    warning = None
    if recognized.confidence is not None and recognized.confidence < 0.6:
        warning = "Low recognition confidence. Please repeat."
    return ProcessResult(
        original_text=recognized.text,
        translation=translated.translation,
        confidence=recognized.confidence,
        key_information=translated.key_information,
        audio_url=f"/audio/{output_path.name}",
        warning=warning,
        timings_ms=timings,
        mode=MODE,
    )


@app.get("/audio/{filename}")
def get_audio(filename: str):
    if len(filename) != 36 or not filename.endswith(".wav"):
        raise HTTPException(404, "Audio not found.")
    try:
        uuid.UUID(hex=filename[:-4])
    except ValueError as exc:
        raise HTTPException(404, "Audio not found.") from exc
    path = AUDIO_DIR / filename
    if not path.is_file():
        raise HTTPException(404, "Audio not found.")
    return FileResponse(path, media_type="audio/wav")
