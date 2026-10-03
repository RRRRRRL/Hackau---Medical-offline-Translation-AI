"""Prepare model assets for the FieldTalk mobile (Flutter) app.

Run this while ONLINE. It downloads/exports the on-device models and copies
them into mobile/assets/models/ so the Flutter app can bundle them. Model
weights are large and are NOT committed to Git (see mobile/.gitignore).

Outputs (into mobile/assets/models/):
  whisper/
    encoder.int8.onnx, decoder.int8.onnx, tokens.txt      -> sherpa-onnx Whisper ASR
  paraformer/
    model.int8.onnx, tokens.txt                           -> sherpa-onnx Paraformer ASR (Chinese)
  voices/{en,ru,zh}/
    {lang}.onnx, tokens.txt, espeak-ng-data/               -> sherpa-onnx Piper TTS
  mt/{en_ru,ru_en,en_zh,zh_en}/
    encoder.onnx, decoder.onnx, decoder_with_past.onnx,
    vocab.json                                             -> onnxruntime MarianMT

Usage:
  python -m scripts.export_models --mt-tiny           # tiny en<->ru
  python -m scripts.export_models --whisper tiny      # whisper tiny
  python -m scripts.export_models --paraformer        # download Chinese Paraformer ASR
  python -m scripts.export_models --all
"""
import argparse
import json
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"
ASSETS = MOBILE / "assets" / "models"
VOICES_DIR = ROOT / "models_local" / "voices"

# Chinese/English/Cantonese Paraformer model (best for Mandarin + mixed speech).
PARAFORMER_HF = "csukuangfj/sherpa-onnx-paraformer-trilingual-zh-cantonese-en"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--whisper", choices=("tiny", "base"), default="tiny")
    parser.add_argument("--mt-tiny", action="store_true", help="export tiny en<->ru")
    parser.add_argument("--mt-zh", action="store_true", help="export en<->zh (larger)")
    parser.add_argument("--mt-only", action="store_true", help="only export MT (skip whisper/voices)")
    parser.add_argument("--paraformer", action="store_true", help="download Chinese Paraformer ASR")
    parser.add_argument("--all", action="store_true", help="export everything")
    args = parser.parse_args()

    ASSETS.mkdir(parents=True, exist_ok=True)
    do_all = args.all

    if do_all or not args.mt_only:
        export_whisper(args.whisper)
        export_piper_voices()
    if do_all or args.paraformer:
        download_paraformer()
    if do_all or args.mt_tiny or args.mt_zh:
        export_mt(tiny=do_all or args.mt_tiny, zh=do_all or args.mt_zh)
    print("Model assets prepared under", ASSETS)


def download_paraformer():
    """Download the Chinese Paraformer ASR model into assets/models/paraformer/.

    This is the trilingual (Mandarin + Cantonese + English) int8 model, which is
    far more accurate and stable on Chinese than Whisper tiny and handles
    Chinese speech mixed with English terms (e.g. drug names).
    """
    dest = ASSETS / "paraformer"
    dest.mkdir(parents=True, exist_ok=True)
    for name in ("model.int8.onnx", "tokens.txt"):
        out = dest / name
        if out.exists():
            print(f"  {name} already present; skipping")
            continue
        url = f"https://huggingface.co/{PARAFORMER_HF}/resolve/main/{name}"
        print(f"  downloading {name} ...")
        urllib.request.urlretrieve(url, out)
        print(f"  saved {name} -> {out}")
    print("Paraformer model ready under", dest)


def export_whisper(size: str):
    """Export a multilingual Whisper model to sherpa-onnx ONNX format."""
    try:
        import sherpa_onnx  # noqa: F401
    except ImportError:
        print("Installing sherpa-onnx for export...")
        subprocess.run([sys.executable, "-m", "pip", "install", "sherpa-onnx"], check=True)
    try:
        from sherpa_onnx import export_whisper
    except ImportError:
        print("sherpa_onnx.export_whisper not available; skipping Whisper export. "
              "If Whisper models are already present in assets/models/whisper/, "
              "this is fine.")
        return
    out = ASSETS / "whisper"
    out.mkdir(parents=True, exist_ok=True)
    print(f"Exporting Whisper {size} -> {out}")
    export_whisper.export(size, str(out))
    # export_whisper writes encoder/decoder .onnx + tokens.txt
    print("Whisper export done.")


def export_piper_voices():
    """Convert the existing Piper ONNX voices to sherpa-onnx layout.

    sherpa-onnx Piper (VITS) needs: model.onnx, tokens.txt and espeak-ng-data.
    """
    import wave

    espeak_src = ROOT / ".venv" / "lib" / "python3.12" / "site-packages" / "piper" / "espeak-ng-data"
    if not espeak_src.exists():
        espeak_src = find_espeak()
    for lang, name in (("en", "en_US-lessac-medium"), ("ru", "ru_RU-irina-medium"), ("zh", "zh_CN-huayan-medium")):
        src_onnx = VOICES_DIR / f"{name}.onnx"
        src_json = VOICES_DIR / f"{name}.onnx.json"
        if not src_onnx.exists():
            print(f"Missing {name}; skipping (run scripts/download_models.py first).")
            continue
        dest = ASSETS / "voices" / lang
        dest.mkdir(parents=True, exist_ok=True)
        # sherpa-onnx expects the model named {lang}.onnx plus tokens.txt.
        shutil.copy2(src_onnx, dest / f"{lang}.onnx")
        write_piper_tokens(src_json, dest / "tokens.txt")
        # Copy espeak-ng-data (grapheme->phoneme) once per voice dir.
        if espeak_src.exists():
            shutil.copytree(espeak_src, dest / "espeak-ng-data", dirs_exist_ok=True)
        print(f"Voice {lang} ready at {dest}")


def write_piper_tokens(json_path: Path, out_path: Path):
    """Extract the phoneme id map from a Piper .onnx.json into a tokens.txt."""
    data = json.loads(json_path.read_text(encoding="utf-8"))
    phoneme_map = data.get("phoneme_id_map", {})
    lines = []
    # Sort by id so index == id (sherpa-onnx VITS expects one token per line).
    for token, ids in phoneme_map.items():
        for pid in ids:
            lines.append((pid, token))
    lines.sort(key=lambda x: x[0])
    # Also include bos/eos/pad placeholders used by sherpa-onnx.
    out_path.write_text("\n".join(tok for _, tok in lines) + "\n", encoding="utf-8")


def export_mt(tiny: bool, zh: bool):
    """Export MarianMT models to ONNX encoder/decoder graphs + SentencePiece.

    tiny=True exports the small en<->ru models (opus-mt_tiny_*).
    zh=True exports the larger en<->zh models (opus-mt-en-zh / zh-en).
    ru<->zh is handled on-device via an English pivot (no model bundled).

    Requires the `optimum` + `optimum-onnx` packages and `optimum-cli`.
    """
    try:
        import optimum  # noqa: F401
        import optimum_onnx  # noqa: F401
    except ImportError:
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "optimum-onnx"], check=True
        )

    pairs = []
    if tiny:
        pairs += [("en", "ru", "Helsinki-NLP/opus-mt_tiny_eng-rus"),
                  ("ru", "en", "Helsinki-NLP/opus-mt_tiny_rus-eng")]
    if zh:
        pairs += [("en", "zh", "Helsinki-NLP/opus-mt-en-zh"),
                  ("zh", "en", "Helsinki-NLP/opus-mt-zh-en")]

    for src, tgt, hf_id in pairs:
        export_one_mt(src, tgt, hf_id)


def export_one_mt(src: str, tgt: str, hf_id: str):
    """Export a single MarianMT model to ONNX using the optimum-cli exporter.

    Writes into ASSETS/mt/{src}_{tgt}/:
      encoder_model.onnx, decoder_model.onnx   (ONNX encoder/decoder graphs)
      source.spm, target.spm                   (SentencePiece models)
      config.json, generation_config.json      (vocab/bos/eos/pad ids)
    """
    dest = ASSETS / "mt" / f"{src}_{tgt}"
    dest.mkdir(parents=True, exist_ok=True)
    print(f"Exporting {hf_id} -> {dest}")

    # optimum-cli lives in the same bin dir as this interpreter (e.g. .venv/bin).
    cli = str(Path(sys.executable).parent / "optimum-cli")
    subprocess.run(
        [
            cli, "export", "onnx",
            "--model", hf_id,
            "--task", "seq2seq-lm",
            "--opset", "18",
            str(dest),
        ],
        check=True,
    )

    # optimum writes encoder_model.onnx/decoder_model.onnx + source.spm/target.spm.
    # generation_config.json carries bos/eos/pad/decoder_start ids the app needs.
    quantize_mt(dest)
    write_vid2sid(dest)
    print(f"Done {hf_id} -> {dest}")


def write_vid2sid(pair_dir: Path):
    """Write vid2sid.json: tokenizer-id -> SentencePiece-id for the target.

    The exported target.spm orders pieces differently than the model's
    vocab.json. The ONNX decoder emits ids in vocab.json order; the app must
    remap those ids back to target.spm ids before decoding to text. This file
    provides that mapping (ids not present here are pad/bos/eos/unk).
    """
    import sentencepiece

    sp = sentencepiece.SentencePieceProcessor(
        model_file=str(pair_dir / "target.spm"))
    vocab = json.loads((pair_dir / "vocab.json").read_text(encoding="utf-8"))
    spm_piece2id = {sp.id_to_piece(i): i for i in range(sp.get_piece_size())}
    vid2sid = {
        str(v): spm_piece2id[piece]
        for piece, v in vocab.items()
        if piece in spm_piece2id
    }
    (pair_dir / "vid2sid.json").write_text(
        json.dumps(vid2sid), encoding="utf-8")
    print(f"  wrote vid2sid.json ({len(vid2sid)} ids)")


def quantize_mt(pair_dir: Path):
    """Dynamic-quantize a Marian ONNX pair to int8 to shrink the APK.

    Dynamic quantization preserves the graph I/O types (int64 in, float out)
    and roughly matches the fp32 quality while cutting the model size ~4x
    (e.g. the 555MB en<->zh models become ~140MB each).
    """
    from onnxruntime.quantization import QuantType, quantize_dynamic

    for name in ("encoder_model.onnx", "decoder_model.onnx"):
        src = pair_dir / name
        if not src.exists():
            continue
        dst = pair_dir / f"{name}.tmp"
        print(f"  quantizing {name} ...")
        quantize_dynamic(str(src), str(dst), weight_type=QuantType.QInt8)
        dst.replace(src)
        print(f"  quantized {name} -> {src.stat().st_size / 1e6:.0f} MB")


def find_espeak() -> Path:
    for p in Path(sys.prefix).glob("**/espeak-ng-data"):
        if p.is_dir():
            return p
    return Path("")


if __name__ == "__main__":
    main()