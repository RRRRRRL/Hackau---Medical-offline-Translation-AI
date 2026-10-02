"""Online setup step. Runtime adapters never download models."""
import subprocess
import sys

from backend.config import ASR_DIR, VOICES, VOICES_DIR


def main():
    from faster_whisper.utils import download_model
    from argostranslate import package

    ASR_DIR.mkdir(parents=True, exist_ok=True)
    VOICES_DIR.mkdir(parents=True, exist_ok=True)
    print("Downloading multilingual faster-whisper base model...")
    download_model("base", output_dir=str(ASR_DIR))
    print("Installing Argos English/Chinese translation packages...")
    package.update_package_index()
    available = package.get_available_packages()
    installed = {(p.from_code, p.to_code) for p in package.get_installed_packages()}
    for source, target in (("en", "zh"), ("zh", "en")):
        if (source, target) in installed:
            continue
        match = next((p for p in available if p.from_code == source and p.to_code == target), None)
        if match is None:
            raise RuntimeError(f"No direct Argos model available for {source}→{target}.")
        package.install_from_path(match.download())
    print("Downloading Piper voices...")
    for voice in VOICES.values():
        subprocess.run(
            [sys.executable, "-m", "piper.download_voices", "--download-dir", str(VOICES_DIR), voice],
            check=True,
        )
    print("Models downloaded. Start the backend with FIELDTALK_MODE=local.")


if __name__ == "__main__":
    main()
