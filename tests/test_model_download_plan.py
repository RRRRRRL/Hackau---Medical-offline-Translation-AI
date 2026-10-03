"""The setup script must not request nonexistent direct pivot packages."""
import sys
from types import SimpleNamespace

from scripts import download_models


def test_setup_downloads_only_direct_argos_pairs(tmp_path, monkeypatch):
    direct_pairs = {('en', 'zh'), ('zh', 'en'), ('en', 'ru'), ('ru', 'en')}
    installed = []
    available = [
        SimpleNamespace(from_code=source, to_code=target, download=lambda pair=(source, target): pair)
        for source, target in sorted(direct_pairs)
    ]
    packages = SimpleNamespace(
        update_package_index=lambda: None,
        get_available_packages=lambda: available,
        get_installed_packages=lambda: [],
        install_from_path=installed.append,
    )
    monkeypatch.setitem(sys.modules, 'argostranslate', SimpleNamespace(package=packages))
    monkeypatch.setitem(sys.modules, 'faster_whisper', SimpleNamespace())
    monkeypatch.setitem(sys.modules, 'faster_whisper.utils', SimpleNamespace(download_model=lambda *args, **kwargs: None))
    monkeypatch.setattr(download_models, 'ASR_DIR', tmp_path / 'asr')
    monkeypatch.setattr(download_models, 'VOICES_DIR', tmp_path / 'voices')
    monkeypatch.setattr(download_models.subprocess, 'run', lambda *args, **kwargs: None)

    download_models.main()

    assert set(installed) == direct_pairs
