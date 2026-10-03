"""Cached, in-process Piper TTS; preserves the local WAV Path contract."""
import math
import struct
import uuid
import wave
from functools import lru_cache
from pathlib import Path
from threading import RLock
from backend.config import AUDIO_DIR, MODE, VOICES, VOICES_DIR
from backend.models.asr import ModelUnavailable

_lock = RLock()

@lru_cache(maxsize=3)
def _voice(language: str):
    name = VOICES.get(language)
    if name is None:
        raise ValueError(f"No voice configured for {language}.")
    model = VOICES_DIR / f"{name}.onnx"
    config = VOICES_DIR / f"{name}.onnx.json"
    if not model.is_file() or not config.is_file():
        raise ModelUnavailable(f"TTS assets missing: {name}. Run scripts.download_models online first.")
    try:
        from piper import PiperVoice
        voice = PiperVoice.load(str(model), config_path=str(config), use_cuda=False)
        if not callable(getattr(voice, "synthesize_wav", None)):
            raise ModelUnavailable("Piper synthesize_wav API missing. Install piper-tts>=1.3,<2.")
        return voice
    except ModelUnavailable:
        raise
    except ImportError as exc:
        raise ModelUnavailable("Install piper-tts>=1.3,<2 first.") from exc
    except Exception as exc:
        raise ModelUnavailable(f"Could not load Piper voice {name}; check assets and dependencies.") from exc

def warmup_tts():
    if MODE == "local":
        with _lock:
            for language in VOICES:
                _voice(language)
    elif MODE != "mock":
        raise ValueError("FIELDTALK_MODE must be mock or local.")

def text_to_speech(text: str, language: str) -> Path:
    if not text.strip():
        raise ValueError("No text to speak.")
    if language not in VOICES:
        raise ValueError(f"No voice configured for {language}.")
    if MODE not in ("mock", "local"):
        raise ValueError("FIELDTALK_MODE must be mock or local.")
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    output = AUDIO_DIR / f"{uuid.uuid4().hex}.wav"
    try:
        if MODE == "mock":
            rate = 16000
            with wave.open(str(output), "wb") as wav:
                wav.setparams((1, 2, rate, 0, "NONE", "not compressed"))
                wav.writeframes(b"".join(struct.pack("<h", int(5000 * math.sin(2 * math.pi * 440 * i / rate)))
                                         for i in range(rate // 3)))
        else:
            with _lock:
                voice = _voice(language)
                with wave.open(str(output), "wb") as wav:
                    voice.synthesize_wav(text, wav)
        with wave.open(str(output), "rb") as wav:
            if wav.getnframes() <= 0:
                raise RuntimeError("Piper produced empty audio.")
        return output
    except (ModelUnavailable, ValueError):
        output.unlink(missing_ok=True)
        raise
    except Exception as exc:
        output.unlink(missing_ok=True)
        raise RuntimeError("Text-to-speech failed; check the local voice and output directory.") from exc
