from std.collections import List
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from yuragi.candidate import (
    CandidateInputBuffer,
    RecordFraming,
    candidates_from_nul_text,
    candidates_from_text,
    render_candidates,
)


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


def test_utf8_is_decoded_only_after_controlled_chunks_are_aggregated() raises:
    var first = List[UInt8](length=4095, fill=UInt8(ord("a")))
    first.append(UInt8(0xE7))

    var second = List[UInt8]()
    second.append(UInt8(0x95))
    second.append(UInt8(0x8C))
    second.append(UInt8(ord("\r")))
    second.append(UInt8(ord("\n")))
    second.append(UInt8(ord("s")))
    second.append(UInt8(ord("e")))
    second.append(UInt8(ord("c")))
    second.append(UInt8(ord("o")))
    second.append(UInt8(ord("n")))
    second.append(UInt8(ord("d")))
    second.append(UInt8(ord("\n")))

    var partial = CandidateInputBuffer()
    partial.append_chunk(first[:])
    with assert_raises(contains="invalid UTF-8"):
        _ = partial.candidates()

    var input = CandidateInputBuffer()
    input.append_chunk(first[:])
    input.append_chunk(second[:])
    var candidates = input.candidates()

    assert_equal(len(candidates), 2)
    assert_equal(candidates[0].source_index, 0)
    assert_equal(candidates[0].text.byte_length(), 4098)
    var first_text_bytes = candidates[0].text.as_bytes()
    for index in range(4095):
        assert_equal(first_text_bytes[index], UInt8(ord("a")))
    assert_equal(first_text_bytes[4095], UInt8(0xE7))
    assert_equal(first_text_bytes[4096], UInt8(0x95))
    assert_equal(first_text_bytes[4097], UInt8(0x8C))
    assert_equal(candidates[1].source_index, 1)
    assert_equal(candidates[1].text, "second")


def test_render_is_newline_delimited() raises:
    var candidates = candidates_from_text("北京大学\nnotes")
    assert_equal(render_candidates(candidates^), "北京大学\nnotes\n")


def test_nul_framing_preserves_newlines_and_carriage_returns() raises:
    var candidates = candidates_from_nul_text("a\nb\r\x00c\r\nd")
    assert_equal(len(candidates), 2)
    assert_equal(candidates[0].text, "a\nb\r")
    assert_equal(candidates[1].text, "c\r\nd")


def test_nul_framing_ignores_only_a_trailing_delimiter() raises:
    var terminated = candidates_from_nul_text("one\x00two\x00")
    assert_equal(len(terminated), 2)
    assert_equal(terminated[0].text, "one")
    assert_equal(terminated[1].text, "two")

    var unterminated = candidates_from_nul_text("one\x00two")
    assert_equal(len(unterminated), 2)
    assert_equal(unterminated[1].text, "two")


def test_nul_framing_preserves_blank_records() raises:
    var candidates = candidates_from_nul_text("\x00\x00last\x00")
    assert_equal(len(candidates), 3)
    assert_equal(candidates[0].text, "")
    assert_equal(candidates[1].text, "")
    assert_equal(candidates[2].text, "last")


def test_input_buffer_dispatches_to_nul_framing() raises:
    var bytes = List[UInt8]()
    bytes.append(UInt8(ord("a")))
    bytes.append(UInt8(ord("\n")))
    bytes.append(UInt8(ord("b")))
    bytes.append(UInt8(0))

    var input = CandidateInputBuffer()
    input.append_chunk(bytes[:])
    var candidates = input.candidates(RecordFraming.NUL)
    assert_equal(len(candidates), 1)
    assert_equal(candidates[0].text, "a\nb")


def test_render_nul_round_trips_candidate_texts() raises:
    var candidates = candidates_from_nul_text("a\nb\x00\x00c")
    var rendered = render_candidates(candidates.copy(), RecordFraming.NUL)
    assert_equal(rendered, "a\nb\x00\x00c\x00")

    var round_tripped = candidates_from_nul_text(rendered)
    assert_equal(len(round_tripped), len(candidates))
    for index in range(len(candidates)):
        assert_equal(round_tripped[index].source_index, candidates[index].source_index)
        assert_equal(round_tripped[index].text, candidates[index].text)


def test_record_framing_equality() raises:
    assert_true(RecordFraming.LINES == RecordFraming.LINES)
    assert_true(RecordFraming.NUL == RecordFraming.NUL)
    assert_false(RecordFraming.LINES == RecordFraming.NUL)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
