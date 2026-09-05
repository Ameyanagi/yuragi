"""Test canonical handoff and require matching release/PR action pins."""

import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/source-artifact.sh"
REQUIRED = (
    "pixi.toml", "pixi.lock", "src/yuragi/main.mojo", "conda.recipe/recipe.yaml",
)


def run(*args, cwd=None, success=True):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if (result.returncode == 0) != success:
        raise AssertionError(f"{args}: {result.stdout}{result.stderr}")


def check_workflows():
    release = (ROOT / ".github/workflows/release.yml").read_text()
    smoke = (ROOT / ".github/workflows/artifact-smoke.yml").read_text()
    for action in ("actions/upload-artifact", "actions/download-artifact", "prefix-dev/setup-pixi"):
        pattern = rf"uses:\s*{re.escape(action)}@([0-9a-f]{{40}})\b"
        release_pins = set(re.findall(pattern, release))
        smoke_pins = set(re.findall(pattern, smoke))
        assert len(release_pins) == 1 and smoke_pins == release_pins, action
    assert "pull_request:" in smoke and "pull_request_target:" not in smoke
    assert "contents: read" in smoke and "contents: write" not in smoke
    assert "gh release" not in smoke
    assert 'branches: [main]' in smoke
    for workflow in (release, smoke):
        assert "scripts/source-artifact.sh create " in workflow
        assert "scripts/source-artifact.sh restore " in workflow
        assert "git archive" not in workflow, "use the shared canonical handoff"
        assert "scripts/check-source-artifact.sh" in workflow


def check_archives():
    with tempfile.TemporaryDirectory(prefix="yuragi-artifact-test-") as folder:
        root = pathlib.Path(folder)
        repo, archives, restored = (root / name for name in ("repo", "archives", "restored"))
        repo.mkdir()
        for name in REQUIRED:
            path = repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"fixture for {name}\n")
        run("git", "init", "--quiet", cwd=repo)
        run("git", "add", ".", cwd=repo)
        run("git", "-c", "user.name=Artifact test", "-c", "user.email=test@example.invalid",
            "commit", "--quiet", "-m", "fixture", cwd=repo)
        run("bash", str(SCRIPT), "create", "HEAD", "yuragi-test", str(archives), cwd=repo)
        run("bash", str(SCRIPT), "restore", "yuragi-test", str(archives), str(restored))
        assert not (restored / ".git").exists()
        for name in REQUIRED:
            assert (restored / name).read_bytes() == (repo / name).read_bytes()
        stale = restored / "stale.mojo"
        stale.write_text("preserve caller-owned files")
        run("bash", str(SCRIPT), "restore", "yuragi-test", str(archives), str(restored), success=False)
        assert stale.read_text() == "preserve caller-owned files"
        run("bash", str(SCRIPT), "restore", "../invalid", str(archives), str(restored), success=False)
        archive = archives / "yuragi-test.tar.gz"
        archive.write_bytes(archive.read_bytes() + b"corrupt")
        rejected = root / "rejected"
        run("bash", str(SCRIPT), "restore", "yuragi-test", str(archives), str(rejected), success=False)
        assert not rejected.exists(), "checksum failure must stop before extraction"


if __name__ == "__main__":
    check_workflows()
    check_archives()
    print("source artifact tests passed (contents, checksum, extraction, destination, input, action parity)")
