"""Bounded candidate ranking and ranked-value contracts."""

from hibana import Matcher
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from yomi import SearchKeyKind

from yuragi.candidate import Candidate, candidates_from_text
from yuragi.ranking import RankedCandidate, rank_candidates, rank_candidates_page


def test_ranked_order_keeps_only_matches() raises:
    var candidates = candidates_from_text("apple\nbanana\nbar\n")
    var ranked = rank_candidates(candidates, Matcher("ba"), len(candidates))

    assert_equal(len(ranked), 2)
    assert_equal(ranked[0].source_index, 1)
    assert_equal(ranked[0].text, "banana")
    assert_equal(ranked[1].source_index, 2)
    assert_equal(ranked[1].text, "bar")


def test_equal_scores_preserve_input_order() raises:
    var candidates = candidates_from_text("xabx\nyaby\n")
    var ranked = rank_candidates(candidates, Matcher("ab"), len(candidates))

    assert_equal(len(ranked), 2)
    assert_equal(ranked[0].score, ranked[1].score)
    assert_equal(ranked[0].source_index, 0)
    assert_equal(ranked[1].source_index, 1)


def test_k_bounds_the_result() raises:
    var candidates = candidates_from_text("apple\nbanana\nbar\n")
    var ranked = rank_candidates(candidates, Matcher("ba"), 1)

    assert_equal(len(ranked), 1)
    assert_equal(ranked[0].text, "banana")


def test_page_counts_matches_before_top_k_truncation() raises:
    var candidates = candidates_from_text("apple\nbanana\nbar\n")
    var page = rank_candidates_page(candidates, Matcher("ba"), 1)

    assert_equal(len(page.rows), 1)
    assert_equal(page.rows[0].text, "banana")
    assert_equal(page.total_matches, 2)


def test_empty_candidate_span_avoids_top_k_construction() raises:
    var candidates = List[Candidate]()
    var ranked = rank_candidates(candidates, Matcher("anything"), 0)

    assert_equal(len(ranked), 0)


def test_ranked_candidate_is_equatable() raises:
    var positions: List[Int] = [0, 2]
    var same_positions: List[Int] = [0, 2]
    var source_positions: List[Int] = [0, 2]
    var text_positions: List[Int] = [0, 2]
    var score_positions: List[Int] = [0, 2]
    var different_positions: List[Int] = [0, 1]
    var ranked = RankedCandidate(2, String("alpha"), 345, positions^)
    var same = RankedCandidate(2, String("alpha"), 345, same_positions^)
    var different_source = RankedCandidate(3, String("alpha"), 345, source_positions^)
    var different_text = RankedCandidate(2, String("beta"), 345, text_positions^)
    var different_score = RankedCandidate(2, String("alpha"), 344, score_positions^)
    var different_position = RankedCandidate(
        2, String("alpha"), 345, different_positions^
    )
    var kind_positions: List[Int] = [0, 2]
    var different_kind = RankedCandidate(
        2,
        String("alpha"),
        345,
        kind_positions^,
        SearchKeyKind.CHINESE_PINYIN_JOINED,
    )

    assert_true(ranked == same)
    assert_false(ranked == different_source)
    assert_false(ranked == different_text)
    assert_false(ranked == different_score)
    assert_false(ranked == different_position)
    assert_false(ranked == different_kind)


def test_positions_are_strictly_increasing_scalar_indices() raises:
    var candidates = candidates_from_text("a界b\n")
    var ranked = rank_candidates(candidates, Matcher("ab"), 1)

    assert_equal(len(ranked), 1)
    assert_equal(len(ranked[0].positions), 2)
    assert_equal(ranked[0].positions[0], 0)
    assert_equal(ranked[0].positions[1], 2)
    for index in range(1, len(ranked[0].positions)):
        assert_true(ranked[0].positions[index - 1] < ranked[0].positions[index])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
