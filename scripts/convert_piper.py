"""Convert raw Piper voices to sherpa-onnx-compatible Piper (VITS) models.

sherpa-onnx requires the .onnx model to embed specific metadata
(model_type=vits, comment=piper, has_espeak=1, etc.) plus a tokens.txt file
with one `token id` pair per line. A raw Piper model (as downloaded from
rhasspy/piper-voices) does NOT have this metadata, so sherpa-onnx rejects it.

Run this once while the laptop model stack is set up (see models_local/voices).
It writes converted .onnx + corrected tokens.txt into mobile/assets/models/voices.

Usage:
  python -m scripts.convert_piper
"""
import json
import shutil
from pathlib import Path

import onnx

ROOT = Path(__file__).resolve().parents[1]
VOICES_SRC = ROOT / "models_local" / "voices"
VOICES_OUT = ROOT / "mobile" / "assets" / "models" / "voices"

VOICES = {
    "en": "en_US-lessac-medium",
    "ru": "ru_RU-irina-medium",
    "zh": "zh_CN-huayan-medium",
}


def add_meta_data(filename: Path, meta_data: dict) -> None:
    """Add metadata props to an ONNX model in place."""
    model = onnx.load(str(filename))
    for key, value in meta_data.items():
        prop = model.metadata_props.add()
        prop.key = key
        prop.value = str(value)
    onnx.save(model, str(filename))


def generate_tokens(config: dict, out_path: Path) -> None:
    """Write tokens.txt with one `token id` pair per line (sherpa-onnx format)."""
    id_map = config["phoneme_id_map"]
    with out_path.open("w", encoding="utf-8") as f:
        for symbol, ids in id_map.items():
            f.write(f"{symbol} {ids[0]}\n")


def main() -> None:
    for lang, name in VOICES.items():
        src_onnx = VOICES_SRC / f"{name}.onnx"
        src_json = VOICES_SRC / f"{name}.onnx.json"
        if not src_onnx.exists() or not src_json.exists():
            print(f"Missing {name}; skipping.")
            continue

        config = json.loads(src_json.read_text(encoding="utf-8"))
        dest_dir = VOICES_OUT / lang
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest_onnx = dest_dir / f"{lang}.onnx"

        # Copy the model, then embed sherpa-onnx metadata in the copy.
        shutil.copy2(src_onnx, dest_onnx)
        meta_data = {
            "model_type": "vits",
            "comment": "piper",  # must be "piper" for models from piper
            "language": config.get("language", {}).get("name_english", lang),
            "voice": config.get("espeak", {}).get("voice", ""),
            "has_espeak": 1,
            "n_speakers": config.get("num_speakers", 1),
            "sample_rate": config.get("audio", {}).get("sample_rate", 22050),
        }
        add_meta_data(dest_onnx, meta_data)

        generate_tokens(config, dest_dir / "tokens.txt")
        print(f"{lang}: converted {name} -> {dest_onnx.name} "
              f"(voice={meta_data['voice']}, sr={meta_data['sample_rate']})")

    print("Piper conversion done.")


if __name__ == "__main__":
    main()