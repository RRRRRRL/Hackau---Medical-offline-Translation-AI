"""Independent web-review endpoints using the existing speech adapters."""
import logging
import tempfile
import time
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from backend.config import MODE, SUPPORTED_PAIRS
from backend.models.asr import ModelUnavailable, speech_to_text
from backend.models.translation import translate_and_extract
from backend.models.tts import text_to_speech
from backend.models.transcript_review import MAX_TEXT, ReviewUnavailable, model_status, review_transcript

router = APIRouter(prefix="/api/review", tags=["optional transcript review"])
logger = logging.getLogger("fieldtalk.review")
LANG = Literal["en", "zh", "ru"]
MAX_AUDIO = 10 * 1024 * 1024
SUFFIXES = {".webm", ".wav", ".ogg", ".mp4", ".m4a"}

class ReviewRequest(BaseModel):
    text: str = Field(min_length=1, max_length=MAX_TEXT)
    source_language: LANG
    question_context: str = Field(default="", max_length=200)

class TranslateRequest(BaseModel):
    original_text: str = Field(min_length=1, max_length=MAX_TEXT)
    confirmed_text: str = Field(min_length=1, max_length=MAX_TEXT)
    source_language: LANG
    target_language: LANG
    confirmed: Literal[True]

def require_local():
    if MODE != "local":
        raise HTTPException(409, "Review mode requires FIELDTALK_MODE=local; mock results are not patient statements.")

@router.get("/health")
def health():
    return {"mode": MODE, "review_model": model_status(), "clinical_validation": False}

@router.post("/recognize")
async def recognize(audio: UploadFile = File(...), source_language: str = Form(...)):
    require_local()
    if source_language not in {"en", "zh", "ru"}:
        raise HTTPException(400, "Unsupported source language.")
    suffix = Path(audio.filename or "").suffix.lower()
    if suffix not in SUFFIXES:
        raise HTTPException(400, "Use WebM, WAV, OGG, MP4, or M4A audio.")
    data = await audio.read(MAX_AUDIO + 1)
    await audio.close()
    if not data:
        raise HTTPException(400, "No audio recorded.")
    if len(data) > MAX_AUDIO:
        raise HTTPException(413, "Audio exceeds 10 MB.")
    started = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="fieldtalk-review-") as folder:
        path = Path(folder) / ("input" + suffix)
        path.write_bytes(data)
        try:
            result = await run_in_threadpool(speech_to_text, path, source_language)
        except ModelUnavailable as exc:
            raise HTTPException(503, str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        except Exception as exc:
            logger.exception("ASR review endpoint failed")
            raise HTTPException(500, "Recognition failed. Check backend logs.") from exc
    if len(result.text) > MAX_TEXT:
        raise HTTPException(400, "Turn is too long for this review demo. Record a shorter turn.")
    return {"original_text": result.text, "source_language": source_language,
            "confidence": result.confidence, "mode": MODE,
            "timings_ms": {"asr": round((time.perf_counter() - started) * 1000, 1)}}

@router.post("/suggest")
def suggest(body: ReviewRequest):
    require_local()
    started = time.perf_counter()
    try:
        result = review_transcript(
        body.text,
        body.source_language,
        body.question_context,
    )
    except ReviewUnavailable as exc:
        raise HTTPException(503, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    result["review_ms"] = round((time.perf_counter() - started) * 1000, 1)
    return result

@router.post("/translate")
def translate_confirmed(body: TranslateRequest):
    require_local()
    if (body.source_language, body.target_language) not in SUPPORTED_PAIRS:
        raise HTTPException(400, "Unsupported language pair.")
    text = body.confirmed_text.strip()
    if not text or not body.original_text.strip():
        raise HTTPException(400, "Text cannot be blank.")
    started = time.perf_counter()
    try:
        t0 = time.perf_counter()
        translated = translate_and_extract(text, body.source_language, body.target_language)
        translation_ms = (time.perf_counter() - t0) * 1000
        t0 = time.perf_counter()
        output = text_to_speech(translated.translation, body.target_language)
        tts_ms = (time.perf_counter() - t0) * 1000
    except ModelUnavailable as exc:
        raise HTTPException(503, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except Exception as exc:
        logger.exception("Confirmed translation failed")
        raise HTTPException(500, "Translation or TTS failed. Check backend logs.") from exc
    return {"original_text": body.original_text, "confirmed_text": text,
            "translation": translated.translation, "audio_url": f"/audio/{output.name}",
            "mode": MODE, "timings_ms": {"translation": round(translation_ms, 1),
            "tts": round(tts_ms, 1), "total": round((time.perf_counter() - started) * 1000, 1)}}
