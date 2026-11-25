"""One local model, newline-delimited JSON over stdin/stdout. No network calls."""
import argparse
import json
import os
from pathlib import Path
import sys
import time
import threading

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["DO_NOT_TRACK"] = "1"


class WorkerError(Exception):
    def __init__(self, code, detail=""):
        super().__init__(detail)
        self.code = code


def validate_model(path):
    # faster-whisper falls back to Tokenizer.from_pretrained when tokenizer.json
    # is missing, even for a local directory. Fail before importing the engine.
    required = ("model.bin", "config.json", "tokenizer.json", "preprocessor_config.json")
    missing = [name for name in required if not (path / name).is_file()]
    if missing:
        raise WorkerError("incomplete_model", ", ".join(missing))


def error_message(kind, error, request_id=None):
    emit(type=kind, id=request_id, code=getattr(error, "code", "workerFailure"), error=str(error))


def watch_parent():
    parent = os.getppid()
    if parent <= 1:
        return

    def monitor():
        while True:
            time.sleep(1)
            if os.getppid() != parent:
                # The UI was force-quit while native inference held the model.
                # EOF alone is only observed once inference returns.
                os._exit(0)

    threading.Thread(target=monitor, daemon=True).start()


def emit(**message):
    print(json.dumps(message, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--device", choices=("mps", "cpu"), default="mps")
    parser.add_argument("--beam-size", type=int, choices=(1, 5), default=1)
    args = parser.parse_args()
    watch_parent()
    try:
        validate_model(args.model)
        import ctranslate2
        import numpy as np
        import onnxruntime
        onnxruntime.disable_telemetry_events()
        from faster_whisper import WhisperModel
        if args.device == "mps" and (
            not hasattr(ctranslate2, "get_mps_device_count") or ctranslate2.get_mps_device_count() < 1
        ):
            raise WorkerError("gpu_unavailable")
        model = WhisperModel(
            str(args.model), device=args.device,
            compute_type="float16" if args.device == "mps" else "int8",
            local_files_only=True,
        )
        if model.model.device != args.device:
            raise WorkerError("device_mismatch", model.model.device)
        # Compile Metal kernels before marking the worker ready. The warmup result
        # is intentionally discarded; it is never sent to the app or clipboard.
        if args.device == "mps":
            segments, _ = model.transcribe(
                np.zeros(16000, dtype=np.float32), language="ru", vad_filter=False,
                beam_size=args.beam_size, best_of=1, temperature=0.0,
                condition_on_previous_text=False, max_new_tokens=4,
            )
            list(segments)
    except Exception as error:
        error_message("fatal", error)
        return 1
    emit(type="ready", device=model.model.device, compute_type=model.model.compute_type, beam_size=args.beam_size)
    for line in sys.stdin:
        request_id = None
        try:
            request = json.loads(line)
            if not isinstance(request, dict) or not isinstance(request.get("id"), str):
                raise ValueError("Expected an object with a string request id")
            request_id = request["id"]
            if not isinstance(request.get("audio"), str) or not isinstance(request.get("language", "ru"), str):
                raise ValueError("Audio path and language must be strings")
            audio = Path(request["audio"])
            if not audio.is_file():
                raise ValueError("Audio file not found")
            started = time.perf_counter()
            segments, _ = model.transcribe(
                str(audio), language=request.get("language", "ru") or None,
                vad_filter=True, beam_size=args.beam_size, best_of=1, condition_on_previous_text=False,
            )
            text = " ".join(segment.text.strip() for segment in segments).strip()
            emit(type="result", id=request["id"], text=text, seconds=round(time.perf_counter() - started, 3))
        except Exception as error:
            error_message("error", error, request_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
