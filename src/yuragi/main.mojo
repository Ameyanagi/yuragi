from std.collections import List
from std.io import FileDescriptor
from std.sys import argv, exit, stderr, stdin

from yuragi.candidate import (
    Candidate,
    CandidateInputBuffer,
    RecordFraming,
    render_candidates,
)
from yuragi.config import config_path
from yuragi.doctor import detect_doctor_report
from yuragi.explain import render_explanation
from yuragi.interactive import FinderOutcome, FinderSession
from yuragi.options import CommandKind, Options, parse_options, usage, version_text
from yuragi.pipeline import (
    InitialAutomationAction,
    InitialAutomationDecision,
    initial_automation_indexed,
    matching_backend_required,
    select,
    select_ranked,
    validate_foundation_mode,
)
from yuragi.search_index import SearchIndex
from yuragi.shell import shell_script


def _read_standard_input(framing: RecordFraming) raises -> List[Candidate]:
    """Read standard input once and decode buffered bytes as lossy UTF-8."""
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
    if options.command == CommandKind.SHELL:
        print(shell_script(options.shell), end="")
        return
    if options.command == CommandKind.CONFIG_PATH:
        try:
            print(config_path())
        except error:
            print("yuragi: config error: ", error, sep="", file=stderr)
            exit(2)
        return
    if options.command == CommandKind.DOCTOR:
        try:
            print(detect_doctor_report(), end="")
        except error:
            print("yuragi: doctor error: ", error, sep="", file=stderr)
            exit(2)
        return

    try:
        validate_foundation_mode(options)
    except error:
        print("yuragi: ", error, sep="", file=stderr)
        exit(2)

    if not options.has_filter and FileDescriptor(0).isatty():
        print(
            (
                "yuragi: pipe candidates into yuragi; standard input is the only "
                "candidate source"
            ),
            file=stderr,
        )
        exit(2)

    var candidates = List[Candidate]()
    try:
        var input_framing = RecordFraming.NUL if options.read0 else RecordFraming.LINES
        candidates = _read_standard_input(input_framing)
    except error:
        print("yuragi: input error: ", error, sep="", file=stderr)
        exit(2)

    if not options.has_filter:
        var index = SearchIndex(candidates^)
        var initial = InitialAutomationDecision()
        try:
            initial = initial_automation_indexed(index, options)
        except error:
            print("yuragi: internal error: ", error, sep="", file=stderr)
            exit(2)

        var output_framing = (
            RecordFraming.NUL if options.print0 else RecordFraming.LINES
        )
        var action = initial.action
        var total_matches = initial.total_matches
        var initial_matches = initial^.take_matches()
        if action == InitialAutomationAction.ACCEPT:
            var selected = List[Candidate]()
            selected.append(
                Candidate(
                    initial_matches[0].source_index,
                    String(initial_matches[0].text),
                )
            )
            print(render_candidates(selected^, output_framing), end="")
            return
        if action == InitialAutomationAction.EXIT_NO_MATCH:
            exit(1)

        var finder = FinderSession(index^, options, initial_matches^, total_matches)
        var outcome = FinderOutcome.ABORTED
        try:
            outcome = finder.run()
        except error:
            print("yuragi: terminal error: ", error, sep="", file=stderr)
            exit(2)
        if outcome == FinderOutcome.ABORTED:
            exit(130)
        var selected = finder.selection()
        if len(selected) == 0:
            exit(1)
        print(render_candidates(selected^, output_framing), end="")
        return

    try:
        if options.explain:
            var ranked = select_ranked(candidates, options)
            if len(ranked) == 0:
                exit(1)
            print(render_explanation(ranked^), end="")
            return

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
