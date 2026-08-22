"""Deterministic bounded-search orchestration benchmark."""

from std.benchmark import keep
from std.collections import List
from std.time import perf_counter_ns

from yuragi.candidate import Candidate
from yuragi.options import Options
from yuragi.pipeline import search_picker_query


comptime _SAMPLES = 5
comptime _SCAN_BUDGET = 200_000


def _candidates(count: Int) -> List[Candidate]:
    var candidates = List[Candidate](capacity=count)
    for index in range(count):
        var bucket = index % 97
        candidates.append(
            Candidate(
                index,
                String(
                    "workspace/pkg-",
                    bucket,
                    "/src/component-",
                    index,
                    "/view.mojo",
                ),
            )
        )
    return candidates^


def _run(count: Int) raises:
    var candidates = _candidates(count)
    var options = Options()
    options.has_limit = True
    options.limit = 20
    var iterations = max(1, _SCAN_BUDGET // count)

    var warmup = search_picker_query(candidates, "pkgsrcview", options)
    keep(warmup.total_matches)
    keep(len(warmup.rows))

    var best_ns = 0
    var checksum = 0
    var expected_total = warmup.total_matches
    for sample in range(_SAMPLES):
        var sample_checksum = 0
        var started = perf_counter_ns()
        for _ in range(iterations):
            var page = search_picker_query(candidates, "pkgsrcview", options)
            if page.total_matches != expected_total:
                raise Error(
                    "benchmark total match count changed; expected ",
                    expected_total,
                    ", got ",
                    page.total_matches,
                )
            sample_checksum += page.total_matches + len(page.rows)
            keep(page.rows)
        var elapsed = perf_counter_ns() - started
        keep(sample_checksum)
        if sample == 0 or elapsed < best_ns:
            best_ns = elapsed
            checksum = sample_checksum

    print(
        "BENCH yuragi search candidates=",
        count,
        " iterations=",
        iterations,
        " limit=20 query=pkgsrcview total_matches=",
        expected_total,
        " best_total_ns=",
        best_ns,
        " ns_per_search=",
        Float64(best_ns) / Float64(iterations),
        " checksum=",
        checksum,
        sep="",
    )


def main() raises:
    print(
        "BENCH_HEADER yuragi search mojo=1.0.0 samples=5 warmup=1 ",
        "statistic=min scan_budget=200000",
        sep="",
    )
    _run(100)
    _run(10_000)
    _run(100_000)
