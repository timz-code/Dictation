import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPTS = Path(__file__).resolve().parent


class RuntimeGuardTests(unittest.TestCase):
    def test_network_audit_detects_even_caught_dns_attempts(self):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory, "attempt.py")
            script.write_text("import socket\ntry: socket.getaddrinfo('localhost', 80)\nexcept RuntimeError: pass\n")
            result = subprocess.run([sys.executable, "-I", str(SCRIPTS / "network_guard.py"), str(script)], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 91)
            self.assertIn("socket.getaddrinfo", result.stderr)

    def test_worker_parent_monitor_exits_after_parent_is_killed(self):
        worker = SCRIPTS.parent / "Resources/whisper_worker.py"
        child_code = "\n".join([
            "import importlib.util, time",
            "spec = importlib.util.spec_from_file_location('worker', %r)" % str(worker),
            "worker = importlib.util.module_from_spec(spec)",
            "spec.loader.exec_module(worker)",
            "worker.watch_parent()",
            "print('monitor ready', flush=True)",
            "time.sleep(60)",
        ])
        parent_code = "\n".join([
            "import subprocess, sys, time",
            "child = subprocess.Popen([sys.executable, '-I', '-u', '-c', %r], stdout=subprocess.PIPE, text=True)" % child_code,
            "assert child.stdout.readline().strip() == 'monitor ready'",
            "print(child.pid, flush=True)",
            "time.sleep(60)",
        ])
        parent = subprocess.Popen([sys.executable, "-I", "-u", "-c", parent_code], stdout=subprocess.PIPE, text=True)
        child_pid = None
        try:
            self.assertTrue(select.select([parent.stdout], [], [], 5)[0], "Parent setup timed out")
            child_pid = int(parent.stdout.readline())
            parent.kill()
            parent.wait(timeout=5)
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                try:
                    os.kill(child_pid, 0)
                except ProcessLookupError:
                    child_pid = None
                    break
                time.sleep(0.05)
            self.assertIsNone(child_pid, "Orphan worker survived parent termination")
        finally:
            if parent.poll() is None:
                parent.kill()
                parent.wait()
            parent.stdout.close()
            if child_pid:
                try:
                    os.kill(child_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


if __name__ == "__main__":
    unittest.main()
