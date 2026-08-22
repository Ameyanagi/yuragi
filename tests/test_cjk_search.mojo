"""Focused CJK key, weighting, cardinality, and highlight contracts."""

from hibana import CaseMode
from std.collections import List
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from yomi import SearchKeyKind

from yuragi.candidate import candidates_from_text
from yuragi.language import LanguageMode
from yuragi.search_index import SearchIndex


def _assert_positions(actual: List[Int], expected: List[Int], context: String) raises:
    assert_equal(len(actual), len(expected), context)
    for index in range(len(expected)):
        assert_equal(actual[index], expected[index], context)


def test_chinese_full_joined_initials_width_and_unique_count() raises:
    var candidates = candidates_from_text("北京大学\n")
    var index = SearchIndex(candidates^, LanguageMode.ZH)
    assert_true(index.prepared_key_count() >= 4)
    assert_true(index.prepared_key_count() <= 8)

    for query in ["bjdx", "beijing", "bei jing da xue", "ＢＪＤＸ"]:
        var page = index.search(query, CaseMode.SMART_ASCII, 5)
        assert_equal(page.total_matches, 1, query)
        assert_equal(len(page.rows), 1, query)
        assert_equal(page.rows[0].text, "北京大学", query)
        # Several candidate keys fuzzily match the ASCII forms; cardinality is
        # nevertheless the number of candidates, never the number of keys.
        if query == "beijing":
            _assert_positions(page.rows[0].positions, [0, 1], String(query))
        else:
            _assert_positions(page.rows[0].positions, [0, 1, 2, 3], String(query))


def test_chinese_polyphone_and_direct_weighting() raises:
    var polyphone_candidates = candidates_from_text("还没\n")
    var polyphone = SearchIndex(polyphone_candidates^, LanguageMode.ZH)
    var alternate = polyphone.search("huanmei", limit=5)
    assert_equal(alternate.total_matches, 1)
    _assert_positions(alternate.rows[0].positions, [0, 1], "polyphone")

    var weighted_candidates = candidates_from_text("北京\nbeijing\n")
    var weighted = SearchIndex(weighted_candidates^, LanguageMode.ZH)
    var page = weighted.search("beijing", limit=5)
    assert_equal(page.total_matches, 2)
    assert_equal(page.rows[0].text, "beijing")
    assert_equal(page.rows[1].text, "北京")
    assert_true(page.rows[0].key_kind == SearchKeyKind.ORIGINAL)
    assert_true(page.rows[1].key_kind == SearchKeyKind.CHINESE_PINYIN_JOINED)
    assert_true(page.rows[0].score > page.rows[1].score)


def test_chinese_mixed_source_highlight_uses_exact_source_scalars() raises:
    var candidates = candidates_from_text("A北🙂京.txt\n")
    var index = SearchIndex(candidates^, LanguageMode.ZH)
    var page = index.search("beijing", limit=5)
    assert_equal(page.total_matches, 1)
    _assert_positions(page.rows[0].positions, [1, 3], "mixed Chinese")


def test_japanese_romaji_width_numeric_and_kanji_negative_contract() raises:
    var candidates = candidates_from_text("カメラ\nｶﾒﾗ\n8月\n日本語\n")
    var index = SearchIndex(candidates^, LanguageMode.JA)

    var camera = index.search("kamera", limit=8)
    assert_equal(camera.total_matches, 2)
    assert_equal(camera.rows[0].source_index, 0)
    assert_equal(camera.rows[1].source_index, 1)
    assert_true(camera.rows[0].key_kind == SearchKeyKind.JAPANESE_ROMAJI)
    _assert_positions(camera.rows[0].positions, [0, 1, 2], "katakana")
    _assert_positions(camera.rows[1].positions, [0, 1, 2], "halfwidth")

    var month = index.search("hachigatsu", limit=8)
    assert_equal(month.total_matches, 1)
    assert_equal(month.rows[0].text, "8月")
    _assert_positions(month.rows[0].positions, [0, 1], "numeric month")

    var unsupported = index.search("nihongo", limit=8)
    assert_equal(unsupported.total_matches, 0)


def test_japanese_contraction_projects_to_all_source_scalars() raises:
    var candidates = candidates_from_text("ｶﾞ\n")
    var index = SearchIndex(candidates^, LanguageMode.JA)
    var page = index.search("ga", limit=5)
    assert_equal(page.total_matches, 1)
    _assert_positions(page.rows[0].positions, [0, 1], "halfwidth voicing")


def test_korean_all_key_families_and_generated_space() raises:
    var candidates = candidates_from_text("한글\n")
    var index = SearchIndex(candidates^, LanguageMode.KO)
    for query in ["hangeul", "han geul", "ㅎㄱ", "gksrmf"]:
        var page = index.search(query, limit=5)
        assert_equal(page.total_matches, 1, query)
        if query == "hangeul":
            assert_true(page.rows[0].key_kind == SearchKeyKind.KOREAN_ROMANIZED)
        _assert_positions(page.rows[0].positions, [0, 1], query)

    # A generated separator participates in matching but owns no fabricated
    # source range. The two syllable matches still project exactly.
    var spaced = index.search("han geul", limit=5)
    _assert_positions(spaced.rows[0].positions, [0, 1], "generated space")


def test_korean_nfc_nfd_equivalence_and_source_projection() raises:
    var candidates = candidates_from_text("한글\n한글\n")
    var index = SearchIndex(candidates^, LanguageMode.KO)
    var page = index.search("hangeul", limit=5)
    assert_equal(page.total_matches, 2)
    assert_equal(page.rows[0].source_index, 0)
    assert_equal(page.rows[1].source_index, 1)
    _assert_positions(page.rows[0].positions, [0, 1], "NFC")
    _assert_positions(page.rows[1].positions, [0, 1, 2, 3, 4, 5], "NFD")


def test_auto_is_direct_only_and_explicit_modes_do_not_incrementally_prune() raises:
    var auto_candidates = candidates_from_text("北京大学\n")
    var direct = SearchIndex(auto_candidates^, LanguageMode.AUTO)
    assert_equal(direct.search("bjdx", limit=5).total_matches, 0)
    assert_equal(direct.search("北京", limit=5).total_matches, 1)

    var zh_candidates = candidates_from_text("北京大学\n北京站\nnotes\n")
    var zh = SearchIndex(zh_candidates^, LanguageMode.ZH)
    _ = zh.search("b", limit=5)
    _ = zh.search("bj", limit=5)
    assert_false(zh.last_search_was_incremental())
    assert_equal(zh.last_scanned_count(), 3)


def test_auto_prepares_one_direct_key_and_reconstructs_only_finalists() raises:
    var candidates = candidates_from_text("a界b\nalpha\nother\n")
    var index = SearchIndex(candidates^, LanguageMode.AUTO)
    assert_equal(index.prepared_key_count(), 3)

    var page = index.search("ab", limit=3)
    assert_equal(page.total_matches, 1)
    assert_equal(len(page.rows), 1)
    assert_equal(page.rows[0].text, "a界b")
    assert_true(page.rows[0].key_kind == SearchKeyKind.ORIGINAL)
    _assert_positions(page.rows[0].positions, [0, 2], "direct identity")
    assert_equal(index.last_scanned_count(), 3)
    assert_equal(index.last_scored_pair_count(), 3)
    assert_equal(index.last_position_reconstruction_count(), 1)


def test_search_index_rejects_forged_language_mode() raises:
    var candidates = candidates_from_text("alpha\n")
    with assert_raises(contains="unsupported Yuragi language mode"):
        _ = SearchIndex(candidates^, LanguageMode(_value=99))


def test_smart_ascii_uppercase_is_not_bypassed_by_normalized_query() raises:
    var candidates = candidates_from_text("北京大学\n")
    var index = SearchIndex(candidates^, LanguageMode.ZH)
    assert_equal(
        index.search("BJDX", CaseMode.SMART_ASCII, 5).total_matches,
        0,
    )
    assert_equal(
        index.search("ＢＪＤＸ", CaseMode.SMART_ASCII, 5).total_matches,
        1,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
