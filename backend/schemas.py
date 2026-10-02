"""Stable public contracts. Keep keys unchanged when replacing adapters."""
from typing import Any

from pydantic import BaseModel


class ASRResult(BaseModel):
    text: str
    language: str
    confidence: float | None = None


class TranslationResult(BaseModel):
    translation: str
    key_information: dict[str, Any] = {}


class ProcessResult(BaseModel):
    original_text: str
    translation: str
    confidence: float | None
    key_information: dict[str, Any]
    audio_url: str
    warning: str | None
    timings_ms: dict[str, float]
    mode: str
