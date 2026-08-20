from std.collections import List
from std.sys import argv, exit, stderr, stdin

from yuragi.candidate import Candidate, CandidateInputBuffer, render_candidates
from yuragi.options import Options, parse_options, usage, version_text
from yuragi.pipeline import select_without_matching, validate_foundation_mode


def _read_standard_input() raises -> List[Candidate]:
    """Read standard input once through the public descriptor API as UTF-8."""
    var input = CandidateInputBuffer()
    var buffer = List[UInt8](length=4096, fill=0)
    var stream = stdin
    while True:
        var count = stream.read_bytes(buffer[:])
        if count == 0:
            break
        input.append_chunk(buffer[:count])
    return input.candidates()


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
        candidates = _read_standard_input()
    except error:
        print("yuragi: input error: ", error, sep="", file=stderr)
        exit(1)

    try:
        var selected = select_without_matching(candidates^, options)
        print(render_candidates(selected^), end="")
    except error:
        print("yuragi: internal error: ", error, sep="", file=stderr)
        exit(1)
