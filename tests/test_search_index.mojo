"""Persistent search-index correctness and incremental-scan contracts."""

from hibana import CaseMode
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_true

from yuragi.candidate import candidates_from_text
from yuragi.language import LanguageMode
from yuragi.options import Options
from yuragi.pipeline import search_picker_query
from yuragi.search_index import CooperativeSearch, SearchIndex


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


def _assert_huge_limit_matches_candidate_count_limit(
    language: LanguageMode,
    corpus: StringSlice,
    query: StringSlice,
) raises:
    var expected_candidates = candidates_from_text(corpus)
    var expected_index = SearchIndex(expected_candidates^, language)
    var expected = expected_index.search(query, limit=len(expected_index))

    var actual_candidates = candidates_from_text(corpus)
    var actual_index = SearchIndex(actual_candidates^, language)
    var actual = actual_index.search(query, limit=Int.MAX)

    assert_true(actual == expected)
    assert_equal(actual.total_matches, expected.total_matches)
    assert_true(len(actual.rows) <= len(actual_index))


def test_near_int_max_limit_is_capped_before_allocation_for_every_mode() raises:
    _assert_huge_limit_matches_candidate_count_limit(
        LanguageMode.AUTO,
        "alpha\nalpine\nbeta\n",
        "a",
    )
    _assert_huge_limit_matches_candidate_count_limit(
        LanguageMode.JA,
        "カメラ\nテレビ\n",
        "kamera",
    )
    _assert_huge_limit_matches_candidate_count_limit(
        LanguageMode.ZH,
        "北京大学\n上海站\n",
        "bjdx",
    )
    _assert_huge_limit_matches_candidate_count_limit(
        LanguageMode.KO,
        "한글\n서울\n",
        "hangeul",
    )


def test_near_int_max_limit_preserves_empty_and_identity_semantics() raises:
    for language in [
        LanguageMode.AUTO,
        LanguageMode.JA,
        LanguageMode.ZH,
        LanguageMode.KO,
    ]:
        var empty_candidates = candidates_from_text("")
        var empty_index = SearchIndex(empty_candidates^, language)
        var empty_page = empty_index.search("anything", limit=Int.MAX)
        assert_equal(empty_page.total_matches, 0)
        assert_equal(len(empty_page.rows), 0)

        var identity_candidates = candidates_from_text("one\ntwo\n")
        var identity_index = SearchIndex(identity_candidates^, language)
        var identity_page = identity_index.search("", limit=Int.MAX)
        assert_equal(identity_page.total_matches, 2)
        assert_equal(len(identity_page.rows), 2)
        assert_equal(identity_page.rows[0].text, "one")
        assert_equal(identity_page.rows[1].text, "two")


def test_cooperative_batches_preserve_exact_rows_for_each_language() raises:
    var languages: List[LanguageMode] = [
        LanguageMode.AUTO,
        LanguageMode.JA,
        LanguageMode.ZH,
        LanguageMode.KO,
    ]
    var queries: List[String] = ["a", "ka", "bei", "카"]
    for mode in range(len(languages)):
        var candidates = candidates_from_text("camera\nかな\n北京\n카메라\ncamera\n")
        var index = SearchIndex(candidates^, languages[mode])
        var exact = index.search(queries[mode], CaseMode.SMART_ASCII, 3)
        var search = CooperativeSearch(index, queries[mode], CaseMode.SMART_ASCII, 3, 1)
        var turns = 0
        while not search.done():
            var before = search.scanned
            search.advance(index, 1)
            assert_true(search.scanned - before <= 1)
            turns += 1
            assert_true(turns < 100)
        assert_equal(search.total_matches, exact.total_matches)
        var rows = search^.take_rows()
        assert_equal(len(rows), len(exact.rows))
        for row in range(len(rows)):
            assert_true(rows[row] == exact.rows[row])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
