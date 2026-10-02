"""Translation adapter: translate_and_extract(text, source, target)."""
from backend.config import MODE
from backend.models.asr import ModelUnavailable
from backend.models.emergency_nlp import extract_key_information
from backend.schemas import TranslationResult


def translate_and_extract(text: str, source_language: str, target_language: str) -> TranslationResult:
    if not text.strip():
        raise ValueError("No text to translate.")
    if MODE == "mock":
        translation = "我对青霉素过敏。" if target_language == "zh" else "I am allergic to penicillin."
    elif MODE == "local":
        try:
            from argostranslate import package, translate
        except ImportError as exc:
            raise ModelUnavailable("Argos Translate is not installed. Install requirements-local.txt.") from exc
        installed = package.get_installed_packages()
        if not any(p.from_code == source_language and p.to_code == target_language for p in installed):
            raise ModelUnavailable(
                f"Translation model {source_language}→{target_language} is missing. Run the model download script."
            )
        try:
            translation = translate.translate(text, source_language, target_language)
        except Exception as exc:
            raise RuntimeError(f"Translation failed: {exc}") from exc
        if not translation.strip():
            raise RuntimeError("Translation returned empty text.")
    else:
        raise ValueError("FIELDTALK_MODE must be mock or local.")
    return TranslationResult(translation=translation, key_information=extract_key_information(text))
