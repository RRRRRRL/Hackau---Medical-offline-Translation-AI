"""Run with: python -m scripts.benchmark_speech --audio sample.wav --language en"""
import argparse
import csv
import statistics
import time
from pathlib import Path
from backend.config import MODE
from backend.models.asr import speech_to_text
from backend.models.tts import text_to_speech

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", type=Path, required=True)
    parser.add_argument(
        "--language",
        choices=("en", "zh", "ru"),
        required=True,
    )
    parser.add_argument("--tts-text", default=None)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--out", type=Path, default=Path("speech_timings.csv"))
    args = parser.parse_args()
    if MODE != "local":
        parser.error("Set FIELDTALK_MODE=local; mock cannot prove inference.")
    if args.runs < 2:
        parser.error("Use at least two runs for cold and subsequent timings.")
    rows = []
    for run in range(args.runs):
        start = time.perf_counter()
        result = speech_to_text(args.audio, args.language)
        recognized = time.perf_counter()
        audio = text_to_speech(args.tts_text or result.text, args.language)
        end = time.perf_counter()
        audio.unlink(missing_ok=True)
        rows.append(dict(run=run + 1, phase="first_call" if run == 0 else "subsequent",
            asr_ms=round((recognized-start)*1000, 1), tts_ms=round((end-recognized)*1000, 1),
            speech_total_ms=round((end-start)*1000, 1)))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    print({"first_call": rows[0], "subsequent_median_ms": statistics.median(
        r["speech_total_ms"] for r in rows[1:]), "subsequent_max_ms": max(
        r["speech_total_ms"] for r in rows[1:])})

if __name__ == "__main__":
    main()
