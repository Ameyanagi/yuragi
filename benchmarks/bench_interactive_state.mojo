"""Profile-oriented benchmark for large empty-query interactive state."""

from std.benchmark import keep
from std.collections import List
from std.os.env import getenv
from std.time import perf_counter_ns

from yuragi.candidate import Candidate
from yuragi.interactive import FinderSession, _FinderApplication
from yuragi.options import Options


comptime _SAMPLES = 31


def _candidates(count: Int) -> List[Candidate]:
    var output = List[Candidate](capacity=count)
    for index in range(count):
        output.append(Candidate(index, String("candidate-", index, ".mojo")))
    return output^


def _sort(mut values: List[Int]):
    for index in range(1, len(values)):
        var value = values[index]
        var destination = index
        while destination > 0 and values[destination - 1] > value:
            values[destination] = values[destination - 1]
            destination -= 1
        values[destination] = value


def _run(count: Int) raises:
    var source = _candidates(count)
    var options = Options()
    var build_timings = List[Int](capacity=_SAMPLES)
    var copy_timings = List[Int](capacity=_SAMPLES)
    var checksum = 0

    for _ in range(3):
        var candidates = source.copy()
        var session = FinderSession(candidates^, options)
        keep(session._model.total_matches)

    for _ in range(_SAMPLES):
        var candidates = source.copy()
        var started = perf_counter_ns()
        var session = FinderSession(candidates^, options)
        build_timings.append(perf_counter_ns() - started)
        checksum += session._model.total_matches + len(session._model.matches)

        started = perf_counter_ns()
        var application = _FinderApplication(session._model)
        copy_timings.append(perf_counter_ns() - started)
        keep(application.initial_model)

    _sort(build_timings)
    _sort(copy_timings)
    print(
        "BENCH yuragi operation=interactive_empty_state candidates=",
        count,
        " samples=31 statistic=nearest-rank build_p50_ns=",
        build_timings[15],
        " build_p95_ns=",
        build_timings[29],
        " application_copy_p50_ns=",
        copy_timings[15],
        " application_copy_p95_ns=",
        copy_timings[29],
        " checksum=",
        checksum,
        sep="",
    )


def _profile() raises:
    """Run the 100k construction/copy path long enough for sampling."""
    var source = _candidates(100_000)
    var options = Options()
    var checksum = 0
    for _ in range(20_000):
        var candidates = source.copy()
        var session = FinderSession(candidates^, options)
        var application = _FinderApplication(session._model)
        checksum += session._model.total_matches
        keep(application.initial_model)
    print("PROFILE yuragi interactive_state checksum=", checksum, sep="")


def main() raises:
    print(
        "BENCH_HEADER yuragi interactive_state mojo=1.0.0 samples=31 warmup=3 ",
        "workload=deterministic",
        sep="",
    )
    if getenv("YURAGI_PROFILE") == "1":
        _profile()
        return
    _run(10_000)
    _run(100_000)
