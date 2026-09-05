"""Reproducible 100k-corpus mark/accept scaling benchmark (Mojo -O3)."""

from std.benchmark import keep
from std.collections import List
from std.time import perf_counter_ns
from yuragi.candidate import Candidate
from yuragi.interactive import FinderOutcome, FinderSession, _toggle_cursor_mark
from yuragi.options import Options


def run(count: Int) raises:
    var candidates = List[Candidate](capacity=100_000)
    for index in range(100_000):
        candidates.append(Candidate(index, String("北京 カメラ 카메라 ", index)))
    var options = Options()
    options.multi = True
    var session = FinderSession(candidates^, options)
    var mark_start = perf_counter_ns()
    for index in range(count - 1, -1, -1):
        session._model.selected_source_index = index * 2
        _toggle_cursor_mark(session._model)
    var mark_ns = perf_counter_ns() - mark_start
    session._model.outcome = FinderOutcome.ACCEPTED
    var accept_start = perf_counter_ns()
    var selected = session.selection()
    var accept_ns = perf_counter_ns() - accept_start
    debug_assert(len(selected) == count)
    keep(selected)
    print(
        "marks=",
        count,
        " corpus=100000 mark_ns=",
        mark_ns,
        " accept_ns=",
        accept_ns,
        " selected=",
        len(selected),
        sep="",
    )


def main() raises:
    for _ in range(5):
        run(1_000)
        run(10_000)
        run(50_000)
