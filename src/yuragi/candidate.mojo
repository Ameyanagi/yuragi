"""Candidate ingestion and output framing owned by Yuragi."""

from std.collections import List


struct RecordFraming(Copyable, Equatable, ImplicitlyCopyable):
    """Nominal delimiter policy for candidate records."""

    var _value: Int

    comptime LINES = RecordFraming(_value=0)
    comptime NUL = RecordFraming(_value=1)

    def __init__(out self, *, _value: Int):
        self._value = _value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


struct Candidate(Copyable):
    """One candidate and its stable position in the input stream."""

    var source_index: Int
    var text: String

    def __init__(out self, source_index: Int, var text: String):
        self.source_index = source_index
        self.text = text^


struct CandidateInputBuffer(Copyable):
    """Accumulate arbitrary byte chunks before decoding UTF-8 lossily once."""

    var _bytes: List[UInt8]

    def __init__(out self):
        self._bytes = List[UInt8]()

    def append_chunk(mut self, chunk: Span[UInt8, _]):
        """Append one input chunk without interpreting partial UTF-8."""
        for index in range(len(chunk)):
            self._bytes.append(chunk[index])

    def candidates(
        self, framing: RecordFraming = RecordFraming.LINES
    ) -> List[Candidate]:
        """Decode the complete byte stream lossily and split it into candidates."""
        var text = _decode_utf8_lossy(self._bytes[:])
        if framing == RecordFraming.NUL:
            return candidates_from_nul_text(text)
        return candidates_from_text(text)


def _valid_utf8_sequence_length(bytes: Span[UInt8, _], offset: Int) -> Int:
    """Return the valid scalar length at offset, or zero for an invalid byte."""
    var first = Int(bytes[offset])
    if first <= 0x7F:
        return 1

    var expected: Int
    if first >= 0xC2 and first <= 0xDF:
        expected = 2
    elif first >= 0xE0 and first <= 0xEF:
        expected = 3
    elif first >= 0xF0 and first <= 0xF4:
        expected = 4
    else:
        return 0

    if offset + expected > len(bytes):
        return 0
    for index in range(1, expected):
        var continuation = Int(bytes[offset + index])
        if continuation < 0x80 or continuation > 0xBF:
            return 0

    var second = Int(bytes[offset + 1])
    if first == 0xE0 and second < 0xA0:
        return 0
    if first == 0xED and second > 0x9F:
        return 0
    if first == 0xF0 and second < 0x90:
        return 0
    if first == 0xF4 and second > 0x8F:
        return 0
    return expected


def _decode_utf8_lossy(bytes: Span[UInt8, _]) -> String:
    """Replace each invalid UTF-8 byte while preserving maximal valid runs."""
    var decoded = List[UInt8](capacity=len(bytes))
    var run_start = 0
    var offset = 0
    while offset < len(bytes):
        var sequence_length = _valid_utf8_sequence_length(bytes, offset)
        if sequence_length > 0:
            offset += sequence_length
            continue

        for index in range(run_start, offset):
            decoded.append(bytes[index])
        decoded.append(UInt8(0xEF))
        decoded.append(UInt8(0xBF))
        decoded.append(UInt8(0xBD))
        offset += 1
        run_start = offset

    for index in range(run_start, len(bytes)):
        decoded.append(bytes[index])
    return String(from_utf8_lossy=decoded)


def candidates_from_text(text: StringSlice) -> List[Candidate]:
    """Split LF/CRLF input without inventing a trailing candidate."""
    var candidates = List[Candidate]()
    var lines = text.split("\n")
    var line_count = len(lines)
    if line_count > 0 and lines[line_count - 1] == "":
        line_count -= 1
    for index in range(line_count):
        var candidate_text = String(lines[index])
        if index + 1 < len(lines):
            candidate_text = String(lines[index].removesuffix("\r"))
        candidates.append(Candidate(index, candidate_text^))
    return candidates^


def candidates_from_nul_text(text: StringSlice) -> List[Candidate]:
    """Split NUL-delimited input without interpreting CR or LF as framing."""
    var candidates = List[Candidate]()
    var records = text.split("\x00")
    var record_count = len(records)
    if record_count > 0 and records[record_count - 1] == "":
        record_count -= 1
    for index in range(record_count):
        candidates.append(Candidate(index, String(records[index])))
    return candidates^


def render_candidates(
    candidates: List[Candidate], framing: RecordFraming = RecordFraming.LINES
) -> String:
    """Render candidates with the selected terminator in supplied order."""
    var output = String()
    for index in range(len(candidates)):
        output += candidates[index].text
        if framing == RecordFraming.NUL:
            output += "\x00"
        else:
            output += "\n"
    return output
