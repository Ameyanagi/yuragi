"""Persistent search-index correctness and incremental-scan contracts."""

from hibana import CaseMode
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_true

from yuragi.candidate import candidates_from_text
from yuragi.options import Options
from yuragi.pipeline import search_picker_query
from yuragi.search_index import SearchIndex


def test_index_search_matches_exact_ranked_page() raises:
    var candidates = candidates_from_text("apple\nbanana\nbar\na界b\n")
    var index = SearchIndex(candidates^)

    var page = index.search("ab", CaseMode.SMART_ASCII, 3)

    assert_equal(page.total_matches, 1)
    assert_equal(len(page.rows), 1)
    assert_equal(page.rows[0].source_index, 3)
    assert_equal(page.rows[0].text, "a界b")
    assert_equal(len(page.rows[0].positions), 2)
    assert_equal(page.rows[0].positions[0], 0)
    assert_equal(page.rows[0].positions[1], 2)


def test_query_extensions_scan_only_previous_matches() raises:
    var candidates = candidates_from_text("alphabet\nalpine\nbeta\nalpaca\n")
    var index = SearchIndex(candidates^)

    var first = index.search("a", CaseMode.SMART_ASCII, 4)
    assert_equal(first.total_matches, 4)
    assert_equal(index.last_scanned_count(), 4)
    assert_equal(index.last_search_was_incremental(), False)

    var second = index.search("al", CaseMode.SMART_ASCII, 4)
    assert_equal(second.total_matches, 3)
    assert_equal(index.last_scanned_count(), 4)
    assert_equal(index.last_search_was_incremental(), True)

    var third = index.search("alp", CaseMode.SMART_ASCII, 4)
    assert_equal(third.total_matches, 3)
    assert_equal(index.last_scanned_count(), 3)
    assert_equal(index.last_search_was_incremental(), True)


def test_backspace_and_case_mode_changes_force_full_scan() raises:
    var candidates = candidates_from_text("alpha\nalpine\nbeta\nALPHA\n")
    var index = SearchIndex(candidates^)

    _ = index.search("alp", CaseMode.SMART_ASCII, 4)
    _ = index.search("alph", CaseMode.SMART_ASCII, 4)
    assert_equal(index.last_search_was_incremental(), True)

    _ = index.search("alp", CaseMode.SMART_ASCII, 4)
    assert_equal(index.last_search_was_incremental(), False)
    assert_equal(index.last_scanned_count(), 4)

    _ = index.search("ALP", CaseMode.EXACT, 4)
    assert_equal(index.last_search_was_incremental(), False)
    assert_equal(index.last_scanned_count(), 4)


def test_empty_query_is_implicit_identity_without_index_materialization() raises:
    var candidates = candidates_from_text("zero\none\ntwo\nthree\n")
    var index = SearchIndex(candidates^)

    var empty = index.search("", CaseMode.SMART_ASCII, 2)
    assert_equal(empty.total_matches, 4)
    assert_equal(len(empty.rows), 2)
    assert_equal(empty.rows[0].source_index, 0)
    assert_equal(empty.rows[1].source_index, 1)
    assert_equal(index.last_scanned_count(), 0)

    var narrowed = index.search("tw", CaseMode.SMART_ASCII, 2)
    assert_equal(narrowed.total_matches, 1)
    assert_equal(narrowed.rows[0].text, "two")
    assert_equal(index.last_search_was_incremental(), False)
    assert_equal(index.last_scanned_count(), 4)
    assert_equal(len(index._matching_indices), 1)


def test_same_query_reuses_only_the_known_match_set() raises:
    var candidates = candidates_from_text("alpha\nbeta\ngamma\ndelta\n")
    var index = SearchIndex(candidates^)

    var first = index.search("ph", CaseMode.SMART_ASCII, 4)
    assert_equal(first.total_matches, 1)
    assert_equal(index.last_scanned_count(), 4)

    var repeated = index.search("ph", CaseMode.SMART_ASCII, 4)
    assert_true(repeated == first)
    assert_equal(index.last_search_was_incremental(), True)
    assert_equal(index.last_scanned_count(), 1)

    var limited = index.search("ph", CaseMode.SMART_ASCII, 1)
    assert_true(limited == first)
    assert_equal(index.last_scanned_count(), 1)


def test_smart_case_extension_safely_reuses_prior_matches() raises:
    var candidates = candidates_from_text("abc\naBc\nABC\nother\n")
    var index = SearchIndex(candidates^)

    var folded = index.search("a", CaseMode.SMART_ASCII, 4)
    assert_equal(folded.total_matches, 3)
    var exact_extension = index.search("aB", CaseMode.SMART_ASCII, 4)

    assert_equal(exact_extension.total_matches, 1)
    assert_equal(exact_extension.rows[0].text, "aBc")
    assert_equal(index.last_scanned_count(), 3)
    assert_equal(index.last_search_was_incremental(), True)


def test_invalid_limit_does_not_replace_incremental_state() raises:
    var candidates = candidates_from_text("alpha\nalpine\nbeta\n")
    var index = SearchIndex(candidates^)
    var first = index.search("alp", CaseMode.SMART_ASCII, 3)
    assert_equal(first.total_matches, 2)

    try:
        _ = index.search("alph", CaseMode.SMART_ASCII, 0)
    except:
        pass
    else:
        raise Error("expected k=0 search to fail")

    var refined = index.search("alph", CaseMode.SMART_ASCII, 3)
    assert_equal(refined.total_matches, 1)
    assert_equal(index.last_search_was_incremental(), True)
    assert_equal(index.last_scanned_count(), 2)


def test_query_edit_sequence_matches_stateless_exact_oracle() raises:
    comptime corpus = (
        "src/app.mojo\nsrc/apple.mojo\ntests/app_test.mojo\nREADME.md\nＡpp.txt\n"
    )
    var indexed_candidates = candidates_from_text(corpus)
    var index = SearchIndex(indexed_candidates^)
    var options = Options()
    options.has_limit = True
    options.limit = 3
    var queries: List[String] = [
        String("a"),
        String("ap"),
        String("app"),
        String("ap"),
        String("A"),
        String("read"),
        String(""),
    ]

    for query_index in range(len(queries)):
        var oracle_candidates = candidates_from_text(corpus)
        var actual = index.search(
            queries[query_index],
            options.case_mode,
            options.limit,
        )
        if queries[query_index] == "":
            assert_equal(actual.total_matches, 5)
            assert_equal(len(actual.rows), 3)
            for row in range(3):
                assert_equal(actual.rows[row].source_index, row)
            continue
        var expected = search_picker_query(
            oracle_candidates,
            queries[query_index],
            options,
        )
        assert_true(
            actual == expected,
            String("incremental index diverged at query index ", query_index),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
