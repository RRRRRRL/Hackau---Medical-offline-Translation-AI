"""Local, turn-based ASR. Preserves FieldTalk's ASRResult contract."""
import os
from functools import lru_cache
from pathlib import Path
from threading import RLock
from backend.config import ASR_DIR, MODE
from backend.schemas import ASRResult

class ModelUnavailable(RuntimeError):
    pass

_lock = RLock()

@lru_cache(maxsize=1)
def _model():
    required = ("model.bin", "config.json", "tokenizer.json")
    if not all((ASR_DIR / name).is_file() for name in required):
        raise ModelUnavailable(f"Incomplete ASR assets at {ASR_DIR}. Run scripts.download_models online first.")
    try:
        from faster_whisper import WhisperModel
        return WhisperModel(str(ASR_DIR), device="cpu", compute_type="int8",
            cpu_threads=int(os.getenv("FIELDTALK_ASR_THREADS", "4")),
            local_files_only=True)
    except ImportError as exc:
        raise ModelUnavailable("Install requirements-local.txt first.") from exc
    except Exception as exc:
        raise ModelUnavailable("Could not load local ASR assets; check model files and dependencies.") from exc

def warmup_asr():
    if MODE == "local":
        with _lock:
            _model()
    elif MODE != "mock":
        raise ValueError("FIELDTALK_MODE must be mock or local.")

def speech_to_text(audio_path: str | Path, language: str | None = None) -> ASRResult:
    path = Path(audio_path)
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError("No audio recorded. Please record again.")
    if language not in (None, "en", "zh", "ru"):
        raise ValueError("Only English, Chinese, and Russian are configured.")
    if MODE == "mock":
        lang = language or "en"
        mock_text = {
            "en": "I am allergic to penicillin.",
            "zh": "我对青霉素过敏。",
            "ru": "У меня аллергия на пенициллин.",
        }
        return ASRResult(
            text=mock_text[lang],
            language=lang,
            confidence=None,
        )
    if MODE != "local":
        raise ValueError("FIELDTALK_MODE must be mock or local.")
    try:
        with _lock:
            segments, info = _model().transcribe(str(path), language=language,
                task="transcribe", beam_size=int(os.getenv("FIELDTALK_ASR_BEAM_SIZE", "5")),
                vad_filter=True, condition_on_previous_text=False)
            # Consume the generator while holding the model lock.
            text = " ".join(segment.text.strip() for segment in segments).strip()
    except ModelUnavailable:
        raise
    except Exception as exc:
        raise RuntimeError("Speech recognition failed; check the recording and local model.") from exc
    if not text:
        raise ValueError("No speech recognized. Please repeat or type your message.")
    return ASRResult(text=text, language=language or info.language, confidence=None)
