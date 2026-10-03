"""Translation adapter: translate_and_extract(text, source, target).

Pairs without a direct Argos package are translated through an English
pivot (e.g. ru -> en -> zh), reusing the installed en<->zh and en<->ru
packages. This keeps the app lightweight and fully offline.
"""
from backend.config import MODE, PIVOT_LANGUAGE, PIVOT_PAIRS
from backend.models.asr import ModelUnavailable
from backend.models.emergency_nlp import extract_key_information
from backend.schemas import TranslationResult

MOCK_TRANSLATIONS = {
    "en": "I am allergic to penicillin.",
    "zh": "我对青霉素过敏。",
    "ru": "У меня аллергия на пенициллин.",
}


def _translate_local(text: str, source_language: str, target_language: str) -> str:
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
        result = translate.translate(text, source_language, target_language)
    except Exception as exc:
        raise RuntimeError(f"Translation failed: {exc}") from exc
    if not result.strip():
        raise RuntimeError("Translation returned empty text.")
    return result


def translate_and_extract(text: str, source_language: str, target_language: str) -> TranslationResult:
    if not text.strip():
        raise ValueError("No text to translate.")
    if MODE == "mock":
        translation = MOCK_TRANSLATIONS[target_language]
    elif MODE == "local":
        if (source_language, target_language) in PIVOT_PAIRS:
            intermediate = _translate_local(text, source_language, PIVOT_LANGUAGE)
            translation = _translate_local(intermediate, PIVOT_LANGUAGE, target_language)
        else:
            translation = _translate_local(text, source_language, target_language)
    else:
        raise ValueError("FIELDTALK_MODE must be mock or local.")
    return TranslationResult(translation=translation, key_information=extract_key_information(text))
