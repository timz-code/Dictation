"""Integration test against the installed model; optionally pass a Russian speech fixture."""
import argparse
import json
from pathlib import Path
import select
import subprocess
import tempfile
import wave


def receive(process, timeout=180):
    if not select.select([process.stdout], [], [], timeout)[0]:
        raise AssertionError("Whisper response timed out")
    line = process.stdout.readline()
    assert line, "Worker exited unexpectedly"
    return json.loads(line)


def send(process, request):
    process.stdin.write(json.dumps(request) + "\n")
    process.stdin.flush()


def main():
    parser = argparse.ArgumentParser()
    base = Path.home() / ".local/share/whisper-ru"
    parser.add_argument("--python", default=str(base / "venv/bin/python"))
    parser.add_argument("--model", default=str(base / "model"))
    parser.add_argument("--speech", type=Path)
    parser.add_argument("--device", choices=("mps", "cpu"), default="mps")
    parser.add_argument("--beam-size", type=int, choices=(1, 5), default=1)
    parser.add_argument("--deny-network", action="store_true", help="macOS: deny all network access and audit Python socket calls")
    args = parser.parse_args()
    worker = Path(__file__).resolve().parent.parent / "Resources/whisper_worker.py"
    command = [args.python, "-I", "-u"]
    if args.deny_network:
        command.append(str(Path(__file__).with_name("network_guard.py")))
    command.extend([str(worker), "--model", args.model, "--device", args.device, "--beam-size", str(args.beam_size)])
    if args.deny_network:
        command = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)"] + command
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        ready = receive(process)
        assert ready["type"] == "ready", ready
        assert ready["device"] == args.device, ready
        assert ready["beam_size"] == args.beam_size, ready
        assert ready["compute_type"] == ("float16" if args.device == "mps" else "int8_float32"), ready
        print("PASS: local model loaded: " + str(ready), flush=True)
        with tempfile.TemporaryDirectory(prefix="dictation-test-") as temp:
            silence = Path(temp) / "silence.wav"
            with wave.open(str(silence), "wb") as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(16000)
                audio.writeframes(b"\0\0" * 16000)
            send(process, {"id": "silence", "audio": str(silence), "language": "ru"})
            response = receive(process)
            assert response["type"] == "result" and response["id"] == "silence" and response["text"] == "", response
            assert response["seconds"] >= 0, response
            print("PASS: silence produces no hallucinated text", flush=True)
            send(process, {"id": "missing", "audio": str(Path(temp) / "missing.wav")})
            response = receive(process)
            assert response["type"] == "error" and response["id"] == "missing"
            print("PASS: missing file returns a structured error", flush=True)
            if args.speech:
                send(process, {"id": "speech", "audio": str(args.speech.resolve()), "language": "ru"})
                response = receive(process)
                assert response["type"] == "result" and response["id"] == "speech", response
                assert "проверка" in response["text"].lower(), response
                assert "речи" in response["text"].lower(), response
                print("PASS: Russian speech after error (%.3fs): %s" % (response["seconds"], response["text"]), flush=True)
            send(process, {"id": "again", "audio": str(silence), "language": "ru"})
            response = receive(process)
            assert response["type"] == "result" and response["id"] == "again" and response["text"] == "", response
            print("PASS: repeated requests reuse the same worker", flush=True)
        process.stdin.close()
        assert process.wait(timeout=10) == 0
        print("PASS: clean shutdown on EOF", flush=True)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


if __name__ == "__main__":
    main()
