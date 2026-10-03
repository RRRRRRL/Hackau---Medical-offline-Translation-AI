"""Configuration shared by all three model adapters."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = Path(os.getenv("FIELDTALK_MODEL_DIR", ROOT / "models_local"))
AUDIO_DIR = Path(os.getenv("FIELDTALK_AUDIO_DIR", ROOT / "generated_audio"))
MODE = os.getenv("FIELDTALK_MODE", "mock").lower()
ASR_DIR = Path(os.getenv("FIELDTALK_ASR_DIR", MODEL_DIR / "whisper-base"))
VOICES_DIR = Path(os.getenv("FIELDTALK_VOICES_DIR", MODEL_DIR / "voices"))
VOICES = {
    "en": "en_US-lessac-medium",
    "zh": "zh_CN-huayan-medium",
    "ru": "ru_RU-irina-medium",
}

LANGUAGES = {"en", "zh", "ru"}

SUPPORTED_PAIRS = {
    ("en", "zh"),
    ("zh", "en"),
    ("en", "ru"),
    ("ru", "en"),
    ("ru", "zh"),
    ("zh", "ru"),
}

# Pairs without a direct Argos package are translated via an English pivot.
PIVOT_LANGUAGE = "en"
PIVOT_PAIRS = {("ru", "zh"), ("zh", "ru")}
