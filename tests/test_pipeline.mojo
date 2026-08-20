from std.collections import List
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from yuragi.candidate import candidates_from_text
from yuragi.options import parse_options
from yuragi.pipeline import matching_backend_required, select_without_matching


def _assert_selection_rejected(var args: List[String]) raises:
    var options = parse_options(args^)
    var candidates = candidates_from_text("candidate\n")
    try:
        _ = select_without_matching(candidates^, options)
    except:
        return
    raise Error("expected selection to be rejected")


def test_empty_filter_is_identity_selection() raises:
    var args: List[String] = ["yuragi", "--filter", ""]
    var options = parse_options(args^)
    var candidates = candidates_from_text("北京大学\nnotes\n")
    assert_false(matching_backend_required(options))
    var selected = select_without_matching(candidates^, options)
    assert_equal(len(selected), 2)
    assert_equal(selected[0].text, "北京大学")
    assert_equal(selected[1].text, "notes")


def test_nonempty_filter_reports_backend_requirement() raises:
    var args: List[String] = ["yuragi", "--filter", "bjdx"]
    var options = parse_options(args^)
    assert_true(matching_backend_required(options))


def test_rejects_unavailable_execution_modes() raises:
    var interactive: List[String] = ["yuragi"]
    _assert_selection_rejected(interactive^)
    var nonempty: List[String] = ["yuragi", "--filter", "bjdx"]
    _assert_selection_rejected(nonempty^)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
