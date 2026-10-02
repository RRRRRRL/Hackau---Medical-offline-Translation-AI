"""ASR adapter: speech_to_text(audio_path, language=None) -> ASRResult."""
from functools import lru_cache
from pathlib import Path

from backend.config import ASR_DIR, MODE
from backend.schemas import ASRResult


class ModelUnavailable(RuntimeError):
    pass


@lru_cache(maxsize=1)
def _model():
    if not (ASR_DIR / "model.bin").is_file():
        raise ModelUnavailable(f"ASR model missing at {ASR_DIR}. Run the model download script.")
    try:
        from faster_whisper import WhisperModel
    except ImportError as exc:
        raise ModelUnavailable("faster-whisper is not installed. Install requirements-local.txt.") from exc
    return WhisperModel(str(ASR_DIR), device="cpu", compute_type="int8", local_files_only=True)


def speech_to_text(audio_path: str | Path, language: str | None = None) -> ASRResult:
    path = Path(audio_path)
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError("No audio recorded. Please record again.")
    if MODE == "mock":
        lang = language or "en"
        text = "I am allergic to penicillin." if lang == "en" else "我对青霉素过敏。"
        return ASRResult(text=text, language=lang, confidence=None)
    if MODE != "local":
        raise ValueError("FIELDTALK_MODE must be mock or local.")
    try:
        segments, info = _model().transcribe(str(path), language=language, beam_size=5, vad_filter=True)
        text = " ".join(segment.text.strip() for segment in segments).strip()
    except ModelUnavailable:
        raise
    except Exception as exc:
        raise RuntimeError(f"Speech recognition failed: {exc}") from exc
    if not text:
        raise ValueError("No speech recognized. Please record again.")
    # Whisper does not expose a calibrated utterance confidence score.
    return ASRResult(text=text, language=language or info.language, confidence=None)
