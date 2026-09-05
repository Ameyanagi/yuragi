"""Read-only environment diagnostics for Yuragi workflows."""

from std.os.env import getenv
from std.pathlib import Path

from yuragi.config import config_path, load_config_file
from yuragi.options import VERSION


def _join(directory: StringSlice, name: StringSlice) -> String:
    if directory == "":
        return String(name)
    var prefix = String(directory)
    if prefix.endswith("/"):
        return prefix + name
    return prefix + "/" + name


def command_on_path(path: StringSlice, name: StringSlice) -> Bool:
    """Return whether PATH names an existing command candidate.

    This is deliberately a filesystem presence diagnostic, not a process spawn
    or an executable-permission claim.
    """
    var directories = path.split(":")
    for index in range(len(directories)):
        var directory = directories[index]
        var candidate = _join(directory, name)
        if directory == "":
            candidate = _join(".", name)
        if Path(candidate).exists():
            return True
    return False


def finder_from_path(path: StringSlice) -> String:
    """Return the generated integrations' preferred available path finder."""
    if command_on_path(path, "fd"):
        return String("fd")
    if command_on_path(path, "fdfind"):
        return String("fdfind")
    if command_on_path(path, "find"):
        return String("find")
    return String()


def doctor_report(
    *,
    resolved_config_path: String,
    config_status: String,
    shell: String,
    finder: String,
) -> String:
    """Format a deterministic report from already-observed host facts."""
    var output = String("Yuragi doctor\n")
    output += "ok version: " + VERSION + "\n"
    output += "ok executable: running\n"
    output += "info config path: " + resolved_config_path + "\n"
    output += "info config file: " + config_status + "\n"
    if shell != "":
        output += "ok shell hint: " + shell + "\n"
    else:
        output += "warn shell hint: SHELL is not set\n"
    if finder != "":
        output += "ok path finder: " + finder + "\n"
    else:
        output += "warn path finder: fd, fdfind, and find were not found on PATH\n"
    output += "info shell scripts: dependencies are checked when each binding runs\n"
    return output^


def detect_doctor_report(*, no_config: Bool = False) raises -> String:
    """Inspect and validate the same file the finder loads, without changing it."""
    var resolved_config_path = String("<disabled>")
    var config_status = String(
        "disabled by --no-config; environment settings still apply"
    )
    if not no_config:
        resolved_config_path = config_path()
        var config = load_config_file(resolved_config_path)
        if config:
            config_status = (
                "loaded and validated; CLI > environment > config > defaults"
            )
        else:
            config_status = "absent; environment and defaults apply"
    return doctor_report(
        resolved_config_path=resolved_config_path,
        config_status=config_status,
        shell=getenv("SHELL"),
        finder=finder_from_path(getenv("PATH")),
    )
