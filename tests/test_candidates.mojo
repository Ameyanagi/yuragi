from std.testing import TestSuite, assert_equal

from yuragi.candidate import candidates_from_text, render_candidates


def test_ingests_unicode_and_preserves_order() raises:
    var candidates = candidates_from_text("北京大学\nnotes\n카메라\n")
    assert_equal(len(candidates), 3)
    assert_equal(candidates[0].source_index, 0)
    assert_equal(candidates[0].text, "北京大学")
    assert_equal(candidates[1].text, "notes")
    assert_equal(candidates[2].text, "카메라")


def test_crlf_and_blank_candidate() raises:
    var candidates = candidates_from_text("one\r\n\r\ntwo\r\n")
    assert_equal(len(candidates), 3)
    assert_equal(candidates[0].text, "one")
    assert_equal(candidates[1].text, "")
    assert_equal(candidates[2].text, "two")


def test_unterminated_final_carriage_return_is_data() raises:
    var candidates = candidates_from_text("final\r")
    assert_equal(len(candidates), 1)
    assert_equal(candidates[0].text, "final\r")


def test_carriage_return_is_stripped_only_before_lf() raises:
    var candidates = candidates_from_text("crlf\r\nembedded\rvalue\nfinal\r")
    assert_equal(len(candidates), 3)
    assert_equal(candidates[0].text, "crlf")
    assert_equal(candidates[1].text, "embedded\rvalue")
    assert_equal(candidates[2].text, "final\r")


def test_only_lf_is_a_record_delimiter() raises:
    var candidates = candidates_from_text("line\u2028separator\n")
    assert_equal(len(candidates), 1)
    assert_equal(candidates[0].text, "line\u2028separator")


def test_render_is_newline_delimited() raises:
    var candidates = candidates_from_text("北京大学\nnotes")
    assert_equal(render_candidates(candidates^), "北京大学\nnotes\n")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
