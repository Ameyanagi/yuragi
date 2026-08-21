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
from yuragi.pipeline import matching_backend_required, select


def _assert_selection_rejected(var args: List[String]) raises:
    var options = parse_options(args^)
    var candidates = candidates_from_text("candidate\n")
    try:
        _ = select(candidates^, options)
    except:
        return
    raise Error("expected selection to be rejected")


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


def test_rejects_unavailable_execution_modes() raises:
    var interactive: List[String] = ["yuragi"]
    _assert_selection_rejected(interactive^)

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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
