#!/usr/bin/env python3
"""Validate bounded pipe producers and interruption while stdin is still open."""
from __future__ import annotations

import signal
import os
import tempfile
import subprocess
import sys
import time
from pathlib import Path


def check(binary: str, environment: dict[str, str]) -> None:
    for flag, value, payload in [
        ("--max-input-bytes", "4", b"a\na\na\n"),
        ("--max-candidates", "2", b"a\nb\nc"),
        ("--max-record-bytes", "3", b"abcd"),
    ]:
        with subprocess.Popen([binary, "--filter", "", flag, value],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=environment,
                              stderr=subprocess.PIPE) as child:
            child.stdin.write(payload)
            child.stdin.flush()
            # Keep stdin open: reaching each budget must fail immediately,
            # including an unterminated extra record, without waiting for EOF.
            assert child.wait(timeout=5) == 2, flag
            assert child.stdout.read() == b"", flag
            diagnostic = child.stderr.read().decode()
            assert flag + "=" + value in diagnostic, diagnostic
            assert "reduce" in diagnostic or "shorten" in diagnostic, diagnostic
    for payload in [b"", b"partial\xe7"]:
        with subprocess.Popen([binary, "--filter", ""], stdin=subprocess.PIPE, env=environment,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
            child.stdin.write(payload)
            child.stdin.flush()
            time.sleep(0.1)
            started = time.monotonic()
            child.send_signal(signal.SIGINT)
            assert child.wait(timeout=5) in (-signal.SIGINT, 130)
            assert time.monotonic() - started < 5
            assert child.stdout.read() == b""
    chunks = [b"a\xe7", b"\x95", b"\x8c\0b\xff", b"\0"]
    with subprocess.Popen([binary, "--filter", "", "--read0", "--print0"],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=environment,
                          stderr=subprocess.PIPE) as child:
        for chunk in chunks:
            child.stdin.write(chunk)
            child.stdin.flush()
            time.sleep(0.01)
        child.stdin.close()
        child.stdin = None
        output, diagnostic = child.communicate(timeout=5)
        assert child.returncode == 0, diagnostic
        assert output == "a界\0b�\0".encode(), output
    print("Input producer limits, chunked UTF-8/read0, and reading cancellation passed.")


def main() -> None:
    binary = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="yuragi-ingestion-config-") as folder:
        environment = os.environ.copy()
        environment["YURAGI_CONFIG_FILE"] = str(Path(folder) / "absent.toml")
        for key in ("YURAGI_LANG", "YURAGI_CASE", "YURAGI_LIMIT"):
            environment.pop(key, None)
        check(binary, environment)


if __name__ == "__main__":
    main()
