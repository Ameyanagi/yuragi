from hibana import CaseMode
from std.collections import List
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from yuragi.options import CommandKind, parse_options, usage, version_text
from yuragi.shell import ShellKind


def _assert_rejected(var args: List[String]) raises:
    try:
        _ = parse_options(args^)
    except:
        return
    raise Error("expected command-line options to be rejected")


def test_filter_and_language_options() raises:
    var args: List[String] = [
        "yuragi",
        "--filter",
        "bjdx",
        "--limit",
        "3",
        "--lang=zh",
    ]
    var options = parse_options(args^)
    assert_true(options.has_filter)
    assert_equal(options.query, "bjdx")
    assert_equal(options.language, "zh")
    assert_true(options.has_language)
    assert_true(options.has_limit)
    assert_equal(options.limit, 3)
    assert_false(options.help_requested)


def test_short_empty_filter() raises:
    var args: List[String] = ["yuragi", "-f", ""]
    var options = parse_options(args^)
    assert_true(options.has_filter)
    assert_equal(options.query, "")
    assert_equal(options.language, "auto")
    assert_false(options.has_language)
    assert_false(options.has_limit)
    assert_equal(options.limit, 0)


def test_interactive_query_and_automation_options() raises:
    var args: List[String] = [
        "yuragi",
        "-q",
        "seed",
        "--select-1",
        "-0",
        "-m",
    ]
    var options = parse_options(args^)
    assert_true(options.has_query)
    assert_equal(options.query, "seed")
    assert_true(options.select_1)
    assert_true(options.exit_0)
    assert_true(options.multi)

    var equals_args: List[String] = [
        "yuragi",
        "--query=equals",
        "-1",
        "--multi",
    ]
    var equals_options = parse_options(equals_args^)
    assert_true(equals_options.has_query)
    assert_equal(equals_options.query, "equals")
    assert_true(equals_options.select_1)
    assert_true(equals_options.multi)


def test_limit_equals_form() raises:
    var args: List[String] = ["yuragi", "--filter=ba", "--limit=12"]
    var options = parse_options(args^)
    assert_true(options.has_limit)
    assert_equal(options.limit, 12)


def test_attached_short_filter_and_query_values() raises:
    var filter_args: List[String] = ["yuragi", "-fba"]
    var filter_options = parse_options(filter_args^)
    assert_true(filter_options.has_filter)
    assert_equal(filter_options.query, "ba")

    var query_args: List[String] = ["yuragi", "-q北"]
    var query_options = parse_options(query_args^)
    assert_true(query_options.has_query)
    assert_equal(query_options.query, "北")


def test_exact_subcommand_shapes() raises:
    var doctor_args: List[String] = ["yuragi", "doctor"]
    assert_true(parse_options(doctor_args^).command == CommandKind.DOCTOR)

    var bash_args: List[String] = ["yuragi", "shell", "bash"]
    var bash = parse_options(bash_args^)
    assert_true(bash.command == CommandKind.SHELL)
    assert_true(bash.shell == ShellKind.BASH)

    var zsh_args: List[String] = ["yuragi", "shell", "zsh"]
    assert_true(parse_options(zsh_args^).shell == ShellKind.ZSH)
    var fish_args: List[String] = ["yuragi", "shell", "fish"]
    assert_true(parse_options(fish_args^).shell == ShellKind.FISH)
    var powershell_args: List[String] = ["yuragi", "shell", "powershell"]
    assert_true(parse_options(powershell_args^).shell == ShellKind.POWERSHELL)

    var config_args: List[String] = ["yuragi", "config", "path"]
    assert_true(parse_options(config_args^).command == CommandKind.CONFIG_PATH)


def test_rejects_malformed_subcommands() raises:
    var doctor_args: List[String] = ["yuragi", "doctor", "extra"]
    with assert_raises(
        contains="doctor accepts only optional --no-config; unexpected argument: extra"
    ):
        _ = parse_options(doctor_args^)

    var missing_shell_args: List[String] = ["yuragi", "shell"]
    with assert_raises(contains="shell requires one of"):
        _ = parse_options(missing_shell_args^)

    var unknown_shell_args: List[String] = ["yuragi", "shell", "nu"]
    with assert_raises(contains="unsupported shell: nu"):
        _ = parse_options(unknown_shell_args^)

    var config_args: List[String] = ["yuragi", "config", "show"]
    with assert_raises(contains="unsupported config action: show"):
        _ = parse_options(config_args^)


def test_help_and_version_text() raises:
    var args: List[String] = ["yuragi", "--help", "--version"]
    var options = parse_options(args^)
    assert_true(options.help_requested)
    assert_true(options.version_requested)
    assert_true(usage().startswith("Usage: yuragi [--filter QUERY | --query QUERY]"))
    assert_true(
        "      --limit N                emit at most N best-ranked candidates"
        in usage()
    )
    assert_true(
        "  -q, --query STR              seed the interactive prompt with STR" in usage()
    )
    assert_true(
        "  -m, --multi                  select multiple candidates with TAB/Shift-TAB"
        in usage()
    )
    assert_true("  +i, --no-ignore-case         match case-sensitively" in usage())
    assert_true(
        "Interactive flag matrix: --query seeds the prompt; --select-1" in usage()
    )
    assert_true("TAB marks and moves down; Shift-TAB marks" in usage())
    assert_true("and moves up in --multi mode" in usage())
    assert_true("Both are inert without --multi" in usage())
    assert_true("Left/Right/Home/End move the query cursor" in usage())
    assert_true("Ctrl-U clears; Ctrl-W deletes the previous word" in usage())
    assert_equal(version_text(), "yuragi 0.1.0")


def test_nul_framing_options() raises:
    var args: List[String] = ["yuragi", "--read0", "--print0"]
    var options = parse_options(args^)
    assert_true(options.read0)
    assert_true(options.print0)


def test_explain_option_and_usage() raises:
    var args: List[String] = ["yuragi", "--filter", "ba", "--explain"]
    var options = parse_options(args^)
    assert_true(options.explain)
    assert_true(
        "      --explain                print rank, score, key kind, and match"
        " positions"
        in usage()
    )


def test_duplicate_value_options_use_the_last_value() raises:
    var filter_args: List[String] = [
        "yuragi",
        "-f",
        "a",
        "--filter=b",
        "--limit",
        "2",
        "--limit=1",
        "--lang",
        "zh",
        "--lang=ko",
    ]
    var filter_options = parse_options(filter_args^)
    assert_equal(filter_options.query, "b")
    assert_equal(filter_options.limit, 1)
    assert_equal(filter_options.language, "ko")

    var query_args: List[String] = ["yuragi", "--query", "a", "-q", "b"]
    var query_options = parse_options(query_args^)
    assert_equal(query_options.query, "b")


def test_duplicate_boolean_options_are_accepted() raises:
    var args: List[String] = [
        "yuragi",
        "--read0",
        "--read0",
        "--print0",
        "--print0",
        "--explain",
        "--explain",
        "--select-1",
        "-1",
        "--exit-0",
        "-0",
        "--multi",
        "-m",
    ]
    var options = parse_options(args^)
    assert_true(options.read0)
    assert_true(options.print0)
    assert_true(options.explain)
    assert_true(options.select_1)
    assert_true(options.exit_0)
    assert_true(options.multi)


def test_rejects_filter_with_interactive_only_flags() raises:
    var query_args: List[String] = [
        "yuragi",
        "--query",
        "x",
        "--filter",
        "y",
    ]
    with assert_raises(contains="--query cannot be used with --filter"):
        _ = parse_options(query_args^)

    var select_args: List[String] = ["yuragi", "--filter", "x", "-1"]
    with assert_raises(contains="--select-1 cannot be used with --filter"):
        _ = parse_options(select_args^)

    var exit_args: List[String] = ["yuragi", "-0", "--filter=x"]
    with assert_raises(contains="--exit-0 cannot be used with --filter"):
        _ = parse_options(exit_args^)

    var multi_args: List[String] = ["yuragi", "-f", "x", "--multi"]
    with assert_raises(contains="--multi cannot be used with --filter"):
        _ = parse_options(multi_args^)


def test_case_mode_defaults_to_smart_ascii() raises:
    var args: List[String] = ["yuragi"]
    var options = parse_options(args^)
    assert_true(options.case_mode == CaseMode.SMART_ASCII)
    assert_false(options.has_case_override)
    assert_false(options.multi)


def test_case_mode_overrides() raises:
    var ignore_args: List[String] = ["yuragi", "-i"]
    var ignore_options = parse_options(ignore_args^)
    assert_true(ignore_options.case_mode == CaseMode.IGNORE_ASCII)
    assert_true(ignore_options.has_case_override)

    var exact_args: List[String] = ["yuragi", "+i"]
    var exact_options = parse_options(exact_args^)
    assert_true(exact_options.case_mode == CaseMode.EXACT)
    assert_true(exact_options.has_case_override)


def test_repeated_case_modes_use_the_last_value() raises:
    var duplicate_ignore: List[String] = [
        "yuragi",
        "--ignore-case",
        "--ignore-case",
    ]
    var duplicate_ignore_options = parse_options(duplicate_ignore^)
    assert_true(duplicate_ignore_options.case_mode == CaseMode.IGNORE_ASCII)

    var duplicate_exact: List[String] = [
        "yuragi",
        "--no-ignore-case",
        "--no-ignore-case",
    ]
    var duplicate_exact_options = parse_options(duplicate_exact^)
    assert_true(duplicate_exact_options.case_mode == CaseMode.EXACT)

    var conflict: List[String] = [
        "yuragi",
        "--ignore-case",
        "--no-ignore-case",
    ]
    var conflict_options = parse_options(conflict^)
    assert_true(conflict_options.case_mode == CaseMode.EXACT)

    var fzf_alias: List[String] = ["yuragi", "-i", "+i"]
    var fzf_alias_options = parse_options(fzf_alias^)
    assert_true(fzf_alias_options.case_mode == CaseMode.EXACT)


def test_rejects_ambiguous_or_invalid_options() raises:
    var missing: List[String] = ["yuragi", "--filter"]
    _assert_rejected(missing^)
    var missing_query: List[String] = ["yuragi", "--query"]
    _assert_rejected(missing_query^)
    var language: List[String] = ["yuragi", "--lang", "en"]
    with assert_raises(
        contains="invalid value 'en' for --lang (possible values: auto, zh, ja, ko)"
    ):
        _ = parse_options(language^)
    var all_language: List[String] = ["yuragi", "--lang", "all"]
    with assert_raises(contains="--lang all is reserved"):
        _ = parse_options(all_language^)
    var plain_language: List[String] = ["yuragi", "--lang", "plain"]
    with assert_raises(contains="--lang plain is reserved"):
        _ = parse_options(plain_language^)
    var positional: List[String] = ["yuragi", "candidate.txt"]
    _assert_rejected(positional^)
    var unknown: List[String] = ["yuragi", "--reverse"]
    with assert_raises(contains="unknown argument '--reverse' (try 'yuragi --help')"):
        _ = parse_options(unknown^)


def test_rejects_invalid_limits() raises:
    var missing: List[String] = ["yuragi", "--limit"]
    _assert_rejected(missing^)
    var zero: List[String] = ["yuragi", "--limit=0"]
    with assert_raises(contains="invalid value '0' for --limit"):
        _ = parse_options(zero^)
    var negative: List[String] = ["yuragi", "--limit", "-2"]
    with assert_raises(contains="invalid value '-2' for --limit"):
        _ = parse_options(negative^)
    var garbage: List[String] = ["yuragi", "--limit=abc"]
    with assert_raises(contains="invalid value 'abc' for --limit"):
        _ = parse_options(garbage^)
    var overflow: List[String] = ["yuragi", "--limit=99999999999999999999"]
    with assert_raises(contains="exceeds the supported integer range"):
        _ = parse_options(overflow^)


def test_doctor_reports_the_actual_unexpected_argument() raises:
    var extra: List[String] = ["yuragi", "doctor", "--no-config", "EXTRA"]
    with assert_raises(contains="unexpected argument: EXTRA"):
        _ = parse_options(extra^)
    var unsupported: List[String] = ["yuragi", "doctor", "--unknown", "EXTRA"]
    with assert_raises(contains="unexpected argument: --unknown"):
        _ = parse_options(unsupported^)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
