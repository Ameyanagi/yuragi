from std.collections import List
from std.sys import argv, exit, stderr, stdin

from yuragi.candidate import (
    Candidate,
    CandidateInputBuffer,
    RecordFraming,
    render_candidates,
)
from yuragi.options import Options, parse_options, usage, version_text
from yuragi.pipeline import matching_backend_required, select, validate_foundation_mode


def _read_standard_input(framing: RecordFraming) raises -> List[Candidate]:
    """Read standard input once through the public descriptor API as UTF-8."""
    var input = CandidateInputBuffer()
    var buffer = List[UInt8](length=4096, fill=0)
    var stream = stdin
    while True:
        var count = stream.read_bytes(buffer[:])
        if count == 0:
            break
        input.append_chunk(buffer[:count])
    return input.candidates(framing)


def _argv_strings() -> List[String]:
    var raw_args = argv()
    var args = List[String]()
    for index in range(len(raw_args)):
        args.append(String(raw_args[index]))
    return args^


def main():
    var options = Options()
    try:
        options = parse_options(_argv_strings())
    except error:
        print("yuragi: ", error, sep="", file=stderr)
        exit(2)

    if options.help_requested:
        print(usage(), end="")
        return
    if options.version_requested:
        print(version_text())
        return

    try:
        validate_foundation_mode(options)
    except error:
        print("yuragi: ", error, sep="", file=stderr)
        exit(2)

    var candidates = List[Candidate]()
    try:
        var input_framing = RecordFraming.NUL if options.read0 else RecordFraming.LINES
        candidates = _read_standard_input(input_framing)
    except error:
        print("yuragi: input error: ", error, sep="", file=stderr)
        exit(2)

    try:
        var selected = select(candidates^, options)
        if matching_backend_required(options) and len(selected) == 0:
            exit(1)
        var output_framing = (
            RecordFraming.NUL if options.print0 else RecordFraming.LINES
        )
        print(render_candidates(selected^, output_framing), end="")
    except error:
        print("yuragi: internal error: ", error, sep="", file=stderr)
        exit(2)
