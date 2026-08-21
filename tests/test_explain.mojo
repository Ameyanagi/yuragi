"""Stable rendering contract for ranked-match explanations."""

from std.collections import List
from std.testing import TestSuite, assert_equal

from yuragi.explain import KEY_KIND_ORIGINAL, render_explanation
from yuragi.ranking import RankedCandidate


def test_render_explanation_golden_output() raises:
    var first_positions: List[Int] = [0, 2]
    var second_positions: List[Int] = [1, 3]
    var ranked = List[RankedCandidate]()
    ranked.append(RankedCandidate(4, String("alpha"), 345, first_positions^))
    ranked.append(RankedCandidate(8, String("be\tta"), 210, second_positions^))

    var rendered = render_explanation(ranked^)
    assert_equal(
        rendered,
        "1\t345\toriginal\t0,2\talpha\n2\t210\toriginal\t1,3\tbe\tta\n",
    )

    var lines = rendered.split("\n")
    var first_fields = lines[0].split("\t")
    var second_fields = lines[1].split("\t")
    assert_equal(first_fields[2], KEY_KIND_ORIGINAL)
    assert_equal(second_fields[2], KEY_KIND_ORIGINAL)
    assert_equal(len(second_fields), 6)


def test_empty_ranked_list_renders_empty_string() raises:
    var ranked = List[RankedCandidate]()
    assert_equal(render_explanation(ranked^), "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
