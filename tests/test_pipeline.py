"""Mock contract tests; real model verification needs downloaded models and a microphone."""
import os
import wave
from io import BytesIO

os.environ["FIELDTALK_MODE"] = "mock"

from fastapi.testclient import TestClient

from backend.main import app
from backend.models.asr import speech_to_text
from backend.models.translation import translate_and_extract
from backend.models.tts import text_to_speech


client = TestClient(app)


def test_asr_contract(tmp_path):
    path = tmp_path / "sample.wav"
    path.write_bytes(b"mock audio")
    result = speech_to_text(path, "en")
    assert result.model_dump() == {"text": "I am allergic to penicillin.", "language": "en", "confidence": None}


def test_translation_contract():
    result = translate_and_extract("I am allergic to penicillin.", "en", "zh")
    assert result.translation == "我对青霉素过敏。"
    assert result.key_information == {}


def test_tts_contract():
    path = text_to_speech("我对青霉素过敏。", "zh")
    with wave.open(str(path), "rb") as audio:
        assert audio.getnframes() > 0
    path.unlink()


def test_mock_end_to_end():
    response = client.post(
        "/process_audio",
        data={"source_language": "en", "target_language": "zh"},
        files={"audio": ("sample.wav", b"mock audio", "audio/wav")},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["original_text"] == "I am allergic to penicillin."
    assert body["translation"] == "我对青霉素过敏。"
    assert body["confidence"] is None
    assert body["mode"] == "mock"
    assert client.get(body["audio_url"]).headers["content-type"] == "audio/wav"


def test_rejects_unsupported_pair():
    response = client.post(
        "/process_audio",
        data={"source_language": "en", "target_language": "en"},
        files={"audio": ("sample.wav", b"mock audio", "audio/wav")},
    )
    assert response.status_code == 400
