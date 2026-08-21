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
    assert_true(usage().startswith("Usage: yuragi --filter QUERY"))
    assert_true(
        "      --limit N         emit at most N best-ranked candidates" in usage()
    )
    assert_equal(version_text(), "yuragi 0.0.0")


def test_nul_framing_options() raises:
    var args: List[String] = ["yuragi", "--read0", "--print0"]
    var options = parse_options(args^)
    assert_true(options.read0)
    assert_true(options.print0)


def test_rejects_duplicate_nul_framing_options() raises:
    var read_args: List[String] = ["yuragi", "--read0", "--read0"]
    with assert_raises(contains="--read0 may be specified only once"):
        _ = parse_options(read_args^)

    var print_args: List[String] = ["yuragi", "--print0", "--print0"]
    with assert_raises(contains="--print0 may be specified only once"):
        _ = parse_options(print_args^)


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
