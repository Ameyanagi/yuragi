from hibana import CaseMode
from std.collections import List
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from yuragi.options import parse_options, usage, version_text


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
    ]
    var options = parse_options(args^)
    assert_true(options.has_query)
    assert_equal(options.query, "seed")
    assert_true(options.select_1)
    assert_true(options.exit_0)

    var equals_args: List[String] = ["yuragi", "--query=equals", "-1"]
    var equals_options = parse_options(equals_args^)
    assert_true(equals_options.has_query)
    assert_equal(equals_options.query, "equals")
    assert_true(equals_options.select_1)


def test_limit_equals_form() raises:
    var args: List[String] = ["yuragi", "--filter=ba", "--limit=12"]
    var options = parse_options(args^)
    assert_true(options.has_limit)
    assert_equal(options.limit, 12)


def test_help_and_version_text() raises:
    var args: List[String] = ["yuragi", "--help", "--version"]
    var options = parse_options(args^)
    assert_true(options.help_requested)
    assert_true(options.version_requested)
    assert_true(usage().startswith("Usage: yuragi [--filter QUERY | --query QUERY]"))
    assert_true(
        "      --limit N         emit at most N best-ranked candidates" in usage()
    )
    assert_true(
        "  -q, --query STR       seed the interactive prompt with STR" in usage()
    )
    assert_true(
        "Interactive flag matrix: --query seeds the prompt; --select-1" in usage()
    )
    assert_equal(version_text(), "yuragi 0.0.0")


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
        "      --explain         print rank, score, key kind, and match positions"
        in usage()
    )


def test_rejects_duplicate_explain_option() raises:
    var args: List[String] = ["yuragi", "--explain", "--explain"]
    with assert_raises(contains="--explain may be specified only once"):
        _ = parse_options(args^)


def test_rejects_duplicate_nul_framing_options() raises:
    var read_args: List[String] = ["yuragi", "--read0", "--read0"]
    with assert_raises(contains="--read0 may be specified only once"):
        _ = parse_options(read_args^)

    var print_args: List[String] = ["yuragi", "--print0", "--print0"]
    with assert_raises(contains="--print0 may be specified only once"):
        _ = parse_options(print_args^)


def test_rejects_duplicate_interactive_automation_options() raises:
    var query_args: List[String] = ["yuragi", "--query", "a", "-q", "b"]
    with assert_raises(contains="--query may be specified only once"):
        _ = parse_options(query_args^)

    var select_args: List[String] = ["yuragi", "--select-1", "-1"]
    with assert_raises(contains="--select-1 may be specified only once"):
        _ = parse_options(select_args^)

    var exit_args: List[String] = ["yuragi", "--exit-0", "-0"]
    with assert_raises(contains="--exit-0 may be specified only once"):
        _ = parse_options(exit_args^)


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


def test_case_mode_defaults_to_smart_ascii() raises:
    var args: List[String] = ["yuragi"]
    var options = parse_options(args^)
    assert_true(options.case_mode == CaseMode.SMART_ASCII)
    assert_false(options.has_case_override)


def test_case_mode_overrides() raises:
    var ignore_args: List[String] = ["yuragi", "-i"]
    var ignore_options = parse_options(ignore_args^)
    assert_true(ignore_options.case_mode == CaseMode.IGNORE_ASCII)
    assert_true(ignore_options.has_case_override)

    var exact_args: List[String] = ["yuragi", "--no-ignore-case"]
    var exact_options = parse_options(exact_args^)
    assert_true(exact_options.case_mode == CaseMode.EXACT)
    assert_true(exact_options.has_case_override)


def test_rejects_duplicate_or_conflicting_case_modes() raises:
    var duplicate_ignore: List[String] = [
        "yuragi",
        "--ignore-case",
        "--ignore-case",
    ]
    with assert_raises(contains="case sensitivity may be specified only once"):
        _ = parse_options(duplicate_ignore^)

    var duplicate_exact: List[String] = [
        "yuragi",
        "--no-ignore-case",
        "--no-ignore-case",
    ]
    with assert_raises(contains="case sensitivity may be specified only once"):
        _ = parse_options(duplicate_exact^)

    var conflict: List[String] = [
        "yuragi",
        "--ignore-case",
        "--no-ignore-case",
    ]
    with assert_raises(contains="case sensitivity may be specified only once"):
        _ = parse_options(conflict^)


def test_rejects_ambiguous_or_invalid_options() raises:
    var duplicate: List[String] = ["yuragi", "-f", "a", "--filter=b"]
    _assert_rejected(duplicate^)
    var missing: List[String] = ["yuragi", "--filter"]
    _assert_rejected(missing^)
    var missing_query: List[String] = ["yuragi", "--query"]
    _assert_rejected(missing_query^)
    var language: List[String] = ["yuragi", "--lang", "en"]
    _assert_rejected(language^)
    var duplicate_language: List[String] = ["yuragi", "--lang", "zh", "--lang=ko"]
    _assert_rejected(duplicate_language^)
    var positional: List[String] = ["yuragi", "candidate.txt"]
    _assert_rejected(positional^)


def test_rejects_invalid_limits() raises:
    var duplicate: List[String] = [
        "yuragi",
        "--filter",
        "a",
        "--limit",
        "2",
        "--limit=1",
    ]
    _assert_rejected(duplicate^)
    var missing: List[String] = ["yuragi", "--limit"]
    _assert_rejected(missing^)
    var zero: List[String] = ["yuragi", "--limit=0"]
    _assert_rejected(zero^)
    var negative: List[String] = ["yuragi", "--limit", "-2"]
    _assert_rejected(negative^)
    var garbage: List[String] = ["yuragi", "--limit=many"]
    _assert_rejected(garbage^)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
