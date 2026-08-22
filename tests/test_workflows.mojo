from std.testing import TestSuite, assert_equal, assert_false, assert_true

from yuragi.config import config_path_from_environment
from yuragi.doctor import command_on_path, doctor_report, finder_from_path
from yuragi.shell import ShellKind, shell_script


def test_config_path_precedence() raises:
    assert_equal(
        config_path_from_environment(
            override="/explicit/yuragi.toml",
            xdg_config_home="/xdg",
            home="/home/person",
        ),
        "/explicit/yuragi.toml",
    )
    assert_equal(
        config_path_from_environment(
            xdg_config_home="/xdg/",
            home="/home/person",
        ),
        "/xdg/yuragi/config.toml",
    )
    assert_equal(
        config_path_from_environment(home="/home/person"),
        "/home/person/.config/yuragi/config.toml",
    )
    assert_equal(
        config_path_from_environment(home="/home/person/"),
        "/home/person/.config/yuragi/config.toml",
    )
    assert_equal(
        config_path_from_environment(
            xdg_config_home="relative/config",
            home="/home/person",
        ),
        "/home/person/.config/yuragi/config.toml",
    )
    try:
        _ = config_path_from_environment()
    except error:
        assert_true("set one of those environment variables" in String(error))
        return
    raise Error("expected an unresolved configuration path to fail")


def test_doctor_report_is_exact_and_warnings_are_in_band() raises:
    assert_equal(
        doctor_report(
            resolved_config_path="/cfg/yuragi/config.toml",
            config_exists=False,
            shell="",
            finder="",
        ),
        (
            "Yuragi doctor\n"
            "ok version: 0.1.0\n"
            "ok executable: running\n"
            "info config path: /cfg/yuragi/config.toml\n"
            "info config file: absent; loading is not enabled in this release\n"
            "warn shell hint: SHELL is not set\n"
            "warn path finder: fd, fdfind, and find were not found on PATH\n"
            "info shell scripts: dependencies are checked when each binding runs\n"
        ),
    )


def test_command_presence_and_finder_precedence() raises:
    assert_true(command_on_path(".", "pixi.toml"))
    assert_false(command_on_path(".", "not-a-yuragi-workflow-command"))
    assert_equal(finder_from_path(""), "")


def test_shell_scripts_cover_the_workflow_contract() raises:
    var bash = shell_script(ShellKind.BASH)
    assert_true(bash.startswith("# yuragi shell integration for bash\n"))
    assert_true("__yuragi_ctrl_t" in bash)
    assert_true("__yuragi_ctrl_r" in bash)
    assert_true("__yuragi_alt_c" in bash)
    assert_true("__yuragi_complete" in bash)
    assert_true("command -v fdfind" in bash)
    assert_true("command -v find" in bash)
    assert_true('"$YURAGI_BIN" --query' in bash)

    var zsh = shell_script(ShellKind.ZSH)
    assert_true("bindkey '^T' __yuragi_ctrl_t" in zsh)
    assert_true("bindkey '^R' __yuragi_ctrl_r" in zsh)
    assert_true("bindkey '^[c' __yuragi_alt_c" in zsh)
    assert_true("bindkey '^I' __yuragi_complete" in zsh)
    assert_false("local selected=$(" in zsh)
    assert_true("local selected\n  selected=$(fc -lnr 1" in zsh)

    var fish = shell_script(ShellKind.FISH)
    assert_true("bind \\ct __yuragi_ctrl_t" in fish)
    assert_true("bind \\cr __yuragi_ctrl_r" in fish)
    assert_true("bind \\ec __yuragi_alt_c" in fish)
    assert_true("bind \\t __yuragi_complete" in fish)

    var powershell = shell_script(ShellKind.POWERSHELL)
    assert_true("Set-PSReadLineKeyHandler -Chord Ctrl+t" in powershell)
    assert_true("Set-PSReadLineKeyHandler -Chord Ctrl+r" in powershell)
    assert_true("Set-PSReadLineKeyHandler -Chord Alt+c" in powershell)
    assert_true("Set-PSReadLineKeyHandler -Chord Tab" in powershell)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
