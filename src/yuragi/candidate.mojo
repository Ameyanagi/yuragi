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


struct InputLimits(Copyable, ImplicitlyCopyable):
    """Validated raw input, record-count, and raw record-byte budgets."""

    var max_input_bytes: Int
    var max_candidates: Int
    var max_record_bytes: Int

    def __init__(out self):
        self.max_input_bytes = 268_435_456
        self.max_candidates = 1_000_000
        self.max_record_bytes = 1_048_576

    def __init__(
        out self,
        max_input_bytes: Int,
        max_candidates: Int = 1_000_000,
        max_record_bytes: Int = 1_048_576,
    ) raises:
        self.max_input_bytes = max_input_bytes
        self.max_candidates = max_candidates
        self.max_record_bytes = max_record_bytes
        self.validate()

    def validate(self) raises:
        """Explicit checkpoint; direct field mutation is otherwise out of contract."""
        if (
            self.max_input_bytes < 1
            or self.max_candidates < 1
            or self.max_record_bytes < 1
        ):
            raise Error(
                "input limits must be positive: max_input_bytes=",
                self.max_input_bytes,
                ", max_candidates=",
                self.max_candidates,
                ", max_record_bytes=",
                self.max_record_bytes,
                "; set each limit to at least 1",
            )


struct CandidateInputBuffer:
    """Frame chunks incrementally, keeping raw bytes for only the current record.

    ASCII LF/NUL cannot occur inside a valid multibyte UTF-8 scalar. Delaying
    decoding until each complete record therefore handles every split-UTF-8
    boundary without retaining whole-stream raw and decoded copies. Invalid
    bytes retain the established one-replacement-per-invalid-byte contract.
    """

    var _record: List[UInt8]
    var _candidates: List[Candidate]
    var _framing: RecordFraming
    var _limits: InputLimits
    var _input_bytes: Int

    def __init__(
        out self,
        framing: RecordFraming = RecordFraming.LINES,
        limits: InputLimits = InputLimits(),
    ):
        self._record = List[UInt8]()
        self._candidates = List[Candidate]()
        self._framing = framing
        self._limits = limits
        self._input_bytes = 0

    def pending_byte_count(self) -> Int:
        return len(self._record)

    def completed_record_count(self) -> Int:
        return len(self._candidates)

    def _finish_record(mut self, terminated: Bool) raises:
        if len(self._candidates) == self._limits.max_candidates:
            raise Error(
                "--max-candidates=",
                self._limits.max_candidates,
                " exceeded by record ",
                len(self._candidates) + 1,
                "; reduce the producer output or raise --max-candidates",
            )
        var length = len(self._record)
        if (
            terminated
            and self._framing == RecordFraming.LINES
            and length > 0
            and self._record[length - 1] == UInt8(13)
        ):
            length -= 1
        var text = _decode_utf8_lossy(self._record[:length])
        self._candidates.append(Candidate(len(self._candidates), text^))
        self._record.clear()

    def append_chunk(mut self, chunk: Span[UInt8, _]) raises:
        """Consume a chunk with fail-before-retain checks at every byte."""
        var delimiter = UInt8(0) if self._framing == RecordFraming.NUL else UInt8(10)
        for index in range(len(chunk)):
            if self._input_bytes == self._limits.max_input_bytes:
                raise Error(
                    "--max-input-bytes=",
                    self._limits.max_input_bytes,
                    " exceeded; reduce the producer output or raise --max-input-bytes",
                )
            self._input_bytes += 1
            if chunk[index] == delimiter:
                self._finish_record(True)
            else:
                if len(self._record) == self._limits.max_record_bytes:
                    raise Error(
                        "--max-record-bytes=",
                        self._limits.max_record_bytes,
                        " exceeded by record ",
                        len(self._candidates) + 1,
                        "; shorten the record or raise --max-record-bytes",
                    )
                # Once the allowed records are complete, reject even an
                # unterminated extra record rather than waiting for EOF.
                if len(self._candidates) == self._limits.max_candidates:
                    raise Error(
                        "--max-candidates=",
                        self._limits.max_candidates,
                        " exceeded by record ",
                        len(self._candidates) + 1,
                        "; reduce the producer output or raise --max-candidates",
                    )
                self._record.append(chunk[index])

    def candidates(var self) raises -> List[Candidate]:
        """Finish an unterminated record and transfer candidate ownership."""
        if len(self._record) > 0:
            self._finish_record(False)
        var candidates = List[Candidate]()
        swap(candidates, self._candidates)
        return candidates^


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
