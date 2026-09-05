#!/usr/bin/env python3
"""Measure p95 terminal frame and abort latency during exact 100k CJK search."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import platform
import select
import statistics
import sys
import time
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "yuragi_pty", Path(__file__).resolve().parents[1] / "scripts/test-pty.py"
)
pty = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pty)
pty.READ_TIMEOUT_SECONDS = 30


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("--samples", type=int, default=31)
    args = parser.parse_args()
    corpus = "".join(f"北京 カメラ 카메라 検索 {i:06d}\n" for i in range(100_000)).encode()
    timings: dict[str, list[float]] = {"key_to_frame_ms": [], "escape_ms": [], "ctrl_c_ms": []}
    for key, name in [(b"\x1b", "escape_ms"), (b"\x03", "ctrl_c_ms")]:
        for sample in range(args.samples):
            def drive(case, master, slave, process, output, screen):
                pty.read_until(case, master, process, output, screen, "initial 100k picker",
                               lambda current: current.contains("matches=100000/100000"))
                started = time.perf_counter_ns()
                os.write(master, "京".encode())
                pty.read_until(case, master, process, output, screen, "query frame while searching",
                               lambda current: current.line(0).startswith("> 京")
                               and current.contains("Searching"))
                timings["key_to_frame_ms"].append((time.perf_counter_ns() - started) / 1e6)
                started = time.perf_counter_ns()
                os.write(master, key)
                deadline = time.monotonic() + 5
                while process.poll() is None and time.monotonic() < deadline:
                    if select.select([master], [], [], 0.001)[0]:
                        pty.read_pty(master, output, screen)
                assert process.poll() == 130
                timings[name].append((time.perf_counter_ns() - started) / 1e6)
            pty.run_case(args.binary.resolve(), f"{name}-{sample}", [], b"", 130,
                         driver=drive, candidates=corpus, check_restoration=True)
    result = {"platform": platform.platform(), "machine": platform.machine(),
              "python": sys.version.split()[0], "corpus_count": 100_000,
              "corpus_sha256": hashlib.sha256(corpus).hexdigest(),
              "query": "京", "statistics": {}}
    for name, values in timings.items():
        values.sort()
        result["statistics"][name] = {"samples": len(values), "p50": statistics.median(values),
                                      "p95": values[(len(values)*95 + 99)//100 - 1],
                                      "max": values[-1], "values_ms": values}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
