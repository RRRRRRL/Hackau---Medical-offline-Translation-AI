"""TTS adapter: text_to_speech(text, language) -> local WAV path."""
import math
import struct
import subprocess
import sys
import uuid
import wave
from pathlib import Path

from backend.config import AUDIO_DIR, MODE, VOICES, VOICES_DIR
from backend.models.asr import ModelUnavailable


def text_to_speech(text: str, language: str) -> Path:
    if not text.strip():
        raise ValueError("No text to speak.")
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    output = AUDIO_DIR / f"{uuid.uuid4().hex}.wav"
    if MODE == "mock":
        # Audible placeholder only. It is not spoken translation.
        rate = 16000
        with wave.open(str(output), "wb") as wav:
            wav.setparams((1, 2, rate, rate // 3, "NONE", "not compressed"))
            frames = b"".join(
                struct.pack("<h", int(5000 * math.sin(2 * math.pi * 440 * i / rate)))
                for i in range(rate // 3)
            )
            wav.writeframes(frames)
        return output
    if MODE != "local":
        raise ValueError("FIELDTALK_MODE must be mock or local.")
    voice = VOICES.get(language)
    if not voice:
        raise ValueError(f"No voice configured for {language}.")
    voice_path = VOICES_DIR / f"{voice}.onnx"
    config_path = VOICES_DIR / f"{voice}.onnx.json"
    if not voice_path.is_file() or not config_path.is_file():
        raise ModelUnavailable(f"TTS voice missing: {voice}. Run the model download script.")
    command = [sys.executable, "-m", "piper", "-m", str(voice_path), "-f", str(output), "--", text]
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", check=False)
    if result.returncode != 0 or not output.is_file() or output.stat().st_size == 0:
        output.unlink(missing_ok=True)
        raise RuntimeError(f"Text-to-speech failed: {result.stderr.strip() or 'Piper produced no audio.'}")
    return output
