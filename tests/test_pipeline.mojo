from std.collections import List
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from yuragi.candidate import candidates_from_text
from yuragi.options import parse_options
from yuragi.pipeline import matching_backend_required, select, validate_foundation_mode


def test_empty_filter_is_identity_selection() raises:
    var args: List[String] = ["yuragi", "--filter", ""]
    var options = parse_options(args^)
    var candidates = candidates_from_text("北京大学\nnotes\n")
    assert_false(matching_backend_required(options))
    var selected = select(candidates^, options)
    assert_equal(len(selected), 2)
    assert_equal(selected[0].text, "北京大学")
    assert_equal(selected[1].text, "notes")


def test_nonempty_filter_uses_matching_backend() raises:
    var args: List[String] = ["yuragi", "--filter", "ba"]
    var options = parse_options(args^)
    assert_true(matching_backend_required(options))

    var candidates = candidates_from_text("apple\nbanana\nbar\n")
    var selected = select(candidates^, options)
    assert_equal(len(selected), 2)
    assert_equal(selected[0].text, "banana")
    assert_equal(selected[1].text, "bar")


def test_accepts_interactive_mode_and_rejects_unavailable_phonetics() raises:
    var interactive: List[String] = ["yuragi"]
    var interactive_options = parse_options(interactive^)
    validate_foundation_mode(interactive_options)

    var phonetic: List[String] = [
        "yuragi",
        "--filter",
        "bjdx",
        "--lang",
        "zh",
    ]
    var options = parse_options(phonetic^)
    var candidates = candidates_from_text("北京大学\n")
    with assert_raises(
        contains=(
            "--lang zh phonetic matching awaits the Yomi integration; direct "
            "matching works without --lang"
        )
    ):
        _ = select(candidates^, options)

    var interactive_phonetic: List[String] = ["yuragi", "--lang", "zh"]
    var interactive_phonetic_options = parse_options(interactive_phonetic^)
    with assert_raises(
        contains=(
            "--lang zh phonetic matching awaits the Yomi integration; direct "
            "matching works without --lang"
        )
    ):
        validate_foundation_mode(interactive_phonetic_options)


def test_explain_mode_validation() raises:
    var interactive_args: List[String] = ["yuragi", "--explain"]
    var interactive_options = parse_options(interactive_args^)
    with assert_raises(
        contains="--explain is a filter-mode report and requires --filter QUERY"
    ):
        validate_foundation_mode(interactive_options)

    var print0_args: List[String] = [
        "yuragi",
        "--filter",
        "ba",
        "--explain",
        "--print0",
    ]
    var print0_options = parse_options(print0_args^)
    with assert_raises(
        contains="--explain writes a line-oriented report and conflicts with --print0"
    ):
        validate_foundation_mode(print0_options)

    var empty_args: List[String] = ["yuragi", "--filter", "", "--explain"]
    var empty_options = parse_options(empty_args^)
    with assert_raises(
        contains=(
            "--explain requires a non-empty --filter query; an empty query "
            "performs no matching"
        )
    ):
        validate_foundation_mode(empty_options)

    var valid_args: List[String] = ["yuragi", "--filter", "ba", "--explain"]
    var valid_options = parse_options(valid_args^)
    assert_equal(valid_options.language, "auto")
    validate_foundation_mode(valid_options)


def test_limit_truncates_empty_filter_selection() raises:
    var args: List[String] = ["yuragi", "--filter", "", "--limit", "2"]
    var options = parse_options(args^)
    var candidates = candidates_from_text("first\nsecond\nthird\n")
    var selected = select(candidates^, options)

    assert_equal(len(selected), 2)
    assert_equal(selected[0].source_index, 0)
    assert_equal(selected[0].text, "first")
    assert_equal(selected[1].source_index, 1)
    assert_equal(selected[1].text, "second")


def test_no_match_returns_empty_selection() raises:
    var args: List[String] = ["yuragi", "--filter", "zz"]
    var options = parse_options(args^)
    var candidates = candidates_from_text("apple\n")
    var selected = select(candidates^, options)

    assert_equal(len(selected), 0)


def test_ignore_case_override_matches_uppercase_query_to_lowercase_text() raises:
    var args: List[String] = [
        "yuragi",
        "--filter",
        "RE",
        "--ignore-case",
    ]
    var options = parse_options(args^)
    var candidates = candidates_from_text("read\n")
    var selected = select(candidates^, options)

    assert_equal(len(selected), 1)
    assert_equal(selected[0].text, "read")


def test_smart_case_uppercase_query_matches_case_sensitively() raises:
    var args: List[String] = ["yuragi", "--filter", "RE"]
    var options = parse_options(args^)
    var candidates = candidates_from_text("read\nREadme\n")
    var selected = select(candidates^, options)

    assert_equal(len(selected), 1)
    assert_equal(selected[0].text, "REadme")


def test_smart_case_lowercase_query_ignores_ascii_case() raises:
    var args: List[String] = ["yuragi", "--filter", "re"]
    var options = parse_options(args^)
    var candidates = candidates_from_text("README\n")
    var selected = select(candidates^, options)

    assert_equal(len(selected), 1)
    assert_equal(selected[0].text, "README")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
