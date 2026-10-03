"""Dependency-stub tests; do not establish real model quality or offline behavior."""
from types import SimpleNamespace
import wave
import pytest
from backend.models import asr, tts

def test_asr_local_contract(tmp_path, monkeypatch):
    audio = tmp_path / "input.wav"; audio.write_bytes(b"test")
    class FakeModel:
        def transcribe(self, path, **kwargs):
            assert kwargs["task"] == "transcribe"
            assert kwargs["condition_on_previous_text"] is False
            return iter([SimpleNamespace(text="I am not allergic.")]), SimpleNamespace(language="en")
    monkeypatch.setattr(asr, "MODE", "local")
    monkeypatch.setattr(asr, "_model", lambda: FakeModel())
    result = asr.speech_to_text(audio, "en")
    assert result.text == "I am not allergic."
    assert result.confidence is None

def test_asr_silence_rejected(tmp_path, monkeypatch):
    audio = tmp_path / "input.wav"; audio.write_bytes(b"test")
    fake = SimpleNamespace(transcribe=lambda *a, **k: (iter([]), SimpleNamespace(language="en")))
    monkeypatch.setattr(asr, "MODE", "local")
    monkeypatch.setattr(asr, "_model", lambda: fake)
    with pytest.raises(ValueError, match="No speech"):
        asr.speech_to_text(audio, "en")

def test_tts_local_wav(tmp_path, monkeypatch):
    class FakeVoice:
        def synthesize_wav(self, text, wav):
            wav.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
            wav.writeframes(b"\x00\x00" * 160)
    monkeypatch.setattr(tts, "MODE", "local")
    monkeypatch.setattr(tts, "AUDIO_DIR", tmp_path)
    monkeypatch.setattr(tts, "_voice", lambda language: FakeVoice())
    output = tts.text_to_speech("hello", "en")
    with wave.open(str(output), "rb") as wav:
        assert wav.getnframes() == 160
    output.unlink()

def test_tts_failure_cleans_output(tmp_path, monkeypatch):
    def fail(text, wav):
        raise RuntimeError("synthetic failure")
    monkeypatch.setattr(tts, "MODE", "local")
    monkeypatch.setattr(tts, "AUDIO_DIR", tmp_path)
    monkeypatch.setattr(tts, "_voice", lambda language: SimpleNamespace(synthesize_wav=fail))
    with pytest.raises(RuntimeError, match="Text-to-speech failed"):
        tts.text_to_speech("hello", "en")
    assert not list(tmp_path.glob("*.wav"))
