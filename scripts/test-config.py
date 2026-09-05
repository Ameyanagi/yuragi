#!/usr/bin/env python3
"""Exercise real settings loading through an isolated compiled CLI process."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1]).resolve())
checks = 0
with tempfile.TemporaryDirectory(prefix="yuragi-config-") as directory:
    root = Path(directory)
    config = root / "config.toml"
    base = os.environ.copy()
    for name in ("YURAGI_CONFIG_FILE", "YURAGI_LANG", "YURAGI_CASE", "YURAGI_LIMIT"):
        base.pop(name, None)
    base["YURAGI_CONFIG_FILE"] = str(config)

    def run(args, *, variables=None, data="READ\nread\n", code=0, output=None, error=None):
        global checks
        environment = base.copy()
        environment.update(variables or {})
        result = subprocess.run(
            [binary, *args], input=data, text=True, capture_output=True,
            env=environment, timeout=10,
        )
        assert result.returncode == code, (args, result.returncode, result.stderr)
        if output is not None:
            assert result.stdout == output, (args, result.stdout, output)
        if error is not None:
            assert error in result.stderr, (args, result.stderr, error)
            assert not result.stdout, (args, result.stdout)
        else:
            assert not result.stderr, (args, result.stderr)
        checks += 1
        return result.stdout

    # Missing default/override files are optional; no file is created.
    run(["--filter", "RE"], output="READ\n")
    assert not config.exists()
    assert "absent; environment and defaults apply" in run(["doctor"])

    config.write_text('lang = "ja"\ncase = "exact"\nlimit = 1\n')
    run(["--filter", "re"], output="read\n")
    assert "loaded and validated" in run(["doctor"])
    run(["--filter", ""], data="one\ntwo\nthree\n", output="one\n")
    run(["--filter", ""], variables={"YURAGI_LIMIT": "2"},
        data="one\ntwo\nthree\n", output="one\ntwo\n")
    run(["--filter", "", "--limit", "3"], variables={"YURAGI_LIMIT": "2"},
        data="one\ntwo\nthree\n", output="one\ntwo\nthree\n")
    run(["--filter", "RE", "--limit", "3"], variables={"YURAGI_CASE": "ignore"},
        output="READ\nread\n")
    run(["--filter", "RE", "--smart-case", "--limit", "3"],
        variables={"YURAGI_CASE": "ignore"}, output="READ\n")
    run(["--filter", "kamera"], data="カメラ\n", output="カメラ\n")
    run(["--filter", "kamera"], variables={"YURAGI_LANG": "auto"},
        data="カメラ\n", output="", code=1)
    run(["--filter", "kamera", "--lang", "ja"],
        variables={"YURAGI_LANG": "auto"}, data="カメラ\n", output="カメラ\n")

    config.write_text('preview = "touch forbidden-marker"\n')
    run(["--filter", ""], code=2, error=f"{config}:1: key 'preview'")
    assert not (root / "forbidden-marker").exists()
    run(["doctor"], code=2, error="remove this unsupported key")
    assert "disabled by --no-config" in run(["doctor", "--no-config"])
    run(["doctor", "--no-config", "EXTRA"], code=2,
        error="unexpected argument: EXTRA; use yuragi doctor [--no-config]")
    run(["--filter", "RE", "--no-config"], output="READ\n")
    # No-config only disables files, and leaves explicit environment settings.
    run(["--filter", "RE", "--no-config"], variables={"YURAGI_CASE": "ignore"},
        output="READ\nread\n")
    run(["--version"], output="yuragi 0.1.0\n")
    assert run(["--help"]).startswith("Usage:")
    assert run(["shell", "bash"]).startswith("# yuragi shell integration")
    run(["config", "path"], output=str(config) + "\n")

    for text, diagnostic in (
        ('lang = "ja\n', "matching single or double quotes"),
        ('limit = "2"\n', "positive decimal integer"),
        ('limit=2\nlimit=3\n', "duplicate limit assignment"),
        ('case="exact"\ncase="smart"\n', "duplicate case assignment"),
        ('[settings]\n', "top-level key = value assignment"),
        ('lang="ja"\n' + '#' * 65536, "at or below 65536 bytes"),
    ):
        config.write_text(text)
        run(["--filter", ""], code=2, error=diagnostic)
    config.write_text('lang="auto"\n')
    run(["--filter", ""], variables={"YURAGI_CASE": "bad"}, code=2,
        error="environment YURAGI_CASE: key 'case' value 'bad'")
    run(["--filter", ""], variables={"YURAGI_LIMIT": "0"}, code=2,
        error="environment YURAGI_LIMIT: key 'limit' value '0'")
    # Directory/FIFO inputs are rejected before opening, so doctor cannot hang.
    run(["doctor"], variables={"YURAGI_CONFIG_FILE": str(root)}, code=2,
        error="not a regular file")
    fifo = root / "fifo"
    os.mkfifo(fifo)
    run(["doctor"], variables={"YURAGI_CONFIG_FILE": str(fifo)}, code=2,
        error="not a regular file")
    if os.geteuid() != 0:
        config.chmod(0)
        try:
            run(["doctor"], code=2, error="make this file readable")
        finally:
            config.chmod(0o600)
        private = root / "inaccessible"
        private.mkdir()
        hidden = private / "config.toml"
        hidden.write_text('lang="ja"\n')
        private.chmod(0)
        try:
            run(["doctor"], variables={"YURAGI_CONFIG_FILE": str(hidden)}, code=2,
                error="make the path accessible")
        finally:
            private.chmod(0o700)
    # --no-config also works in an environment unable to resolve a config path.
    for key in ("HOME", "XDG_CONFIG_HOME", "YURAGI_CONFIG_FILE"):
        base.pop(key, None)
    run(["--no-config", "--filter", "RE"], output="READ\n")
    assert "disabled by --no-config" in run(["doctor", "--no-config"])
print(f"Configuration CLI checks passed: {checks}")
