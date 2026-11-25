"""Test-only launcher: fail on any Python socket connection, DNS lookup or bind.

Run the integration test with --deny-network to also block native networking
through the macOS sandbox. This file is never bundled with the app.
"""
import runpy
import sys

attempts = []


def audit(event, args):
    if event in {"socket.connect", "socket.bind", "socket.getaddrinfo", "socket.gethostbyname", "socket.gethostbyaddr", "socket.sendto"}:
        attempts.append(event)
        raise RuntimeError("Offline test blocked network operation: " + event)


sys.addaudithook(audit)
sys.argv = sys.argv[1:]
try:
    runpy.run_path(sys.argv[0], run_name="__main__")
finally:
    if attempts:
        print("FAIL: network attempts: " + repr(attempts), file=sys.stderr)
        raise SystemExit(91)
    print("PASS: no Python socket/DNS attempts", file=sys.stderr)
