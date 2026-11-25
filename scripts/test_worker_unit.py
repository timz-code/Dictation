"""Fast protocol/offline checks; no model, microphone or network required."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("whisper_worker", Path(__file__).resolve().parents[1] / "Resources/whisper_worker.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class WorkerTests(unittest.TestCase):
    def test_incomplete_model_fails_before_engine_import(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "model.bin").touch()
            output = io.StringIO()
            with patch.object(sys, "argv", ["worker", "--model", directory]), contextlib.redirect_stdout(output):
                self.assertEqual(worker.main(), 1)
            message = json.loads(output.getvalue())
            self.assertEqual(message["type"], "fatal")
            self.assertEqual(message["code"], "incomplete_model")
            self.assertIn("tokenizer.json", message["error"])

    def test_malformed_requests_do_not_crash_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ("model.bin", "config.json", "tokenizer.json", "preprocessor_config.json", "audio.caf"):
                Path(directory, name).touch()
            def transcribe(*args, **kwargs):
                return iter([types.SimpleNamespace(text=" Test transcription. ")]), None
            model = types.SimpleNamespace(model=types.SimpleNamespace(device="cpu", compute_type="int8_float32"), transcribe=transcribe)
            disabled = []
            modules = {
                "ctranslate2": types.SimpleNamespace(),
                "numpy": types.SimpleNamespace(),
                "onnxruntime": types.SimpleNamespace(disable_telemetry_events=lambda: disabled.append(True)),
                "faster_whisper": types.SimpleNamespace(WhisperModel=lambda *args, **kwargs: model),
            }
            requests = ['[]', 'null', '{', '{"id": 1}', '{"id":"bad", "audio": 1}', json.dumps({"id": "valid", "audio": str(Path(directory, "audio.caf"))})]
            output = io.StringIO()
            with patch.dict(sys.modules, modules), patch.object(sys, "argv", ["worker", "--model", directory, "--device", "cpu"]), patch.object(sys, "stdin", io.StringIO("\n".join(requests))), contextlib.redirect_stdout(output):
                self.assertEqual(worker.main(), 0)
            messages = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual(messages[0]["type"], "ready")
            self.assertTrue(all(message["type"] == "error" for message in messages[1:-1]))
            self.assertEqual(messages[-1]["id"], "valid")
            self.assertEqual(messages[-1]["text"], "Test transcription.")
            self.assertEqual(disabled, [True])


if __name__ == "__main__":
    unittest.main()
