"""Candidate ingestion and output framing owned by Yuragi."""

from std.collections import List


struct Candidate(Copyable):
    """One candidate and its stable position in the input stream."""

    var source_index: Int
    var text: String

    def __init__(out self, source_index: Int, var text: String):
        self.source_index = source_index
        self.text = text^


struct CandidateInputBuffer(Copyable):
    """Accumulate arbitrary byte chunks before validating UTF-8 once."""

    var _bytes: List[UInt8]

    def __init__(out self):
        self._bytes = List[UInt8]()

    def append_chunk(mut self, chunk: Span[UInt8, ...]):
        """Append one input chunk without interpreting partial UTF-8."""
        for index in range(len(chunk)):
            self._bytes.append(chunk[index])

    def candidates(self) raises -> List[Candidate]:
        """Validate the complete byte stream and split it into candidates."""
        var text = String(from_utf8=self._bytes[:])
        return candidates_from_text(text)


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


def render_candidates(candidates: List[Candidate]) -> String:
    """Render candidates as newline-delimited output in their supplied order."""
    var output = String()
    for index in range(len(candidates)):
        output += candidates[index].text
        output += "\n"
    return output
