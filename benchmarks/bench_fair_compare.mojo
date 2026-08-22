"""Fair, deterministic Yuru/Yuragi plain-search comparison protocol."""

from hibana import CaseMode
from std.benchmark import keep
from std.collections import List
from std.time import perf_counter_ns

from yuragi.candidate import Candidate
from yuragi.search_index import SearchIndex


comptime _SAMPLES = 31


def _candidates(count: Int) -> List[Candidate]:
    var candidates = List[Candidate](capacity=count)
    for index in range(count):
        candidates.append(
            Candidate(
                index,
                String(
                    "workspace/pkg-",
                    index % 97,
                    "/src/component-",
                    index,
                    "/view.mojo",
                ),
            )
        )
    return candidates^


def _validate_corpus(candidates: Span[Candidate, _], expected_bytes: Int) raises:
    var byte_count = 0
    for index in range(len(candidates)):
        byte_count += candidates[index].text.byte_length()
    if byte_count != expected_bytes:
        raise Error(
            "fair corpus byte count changed; expected ",
            expected_bytes,
            ", got ",
            byte_count,
        )
    if (
        len(candidates) == 0
        or candidates[0].text != "workspace/pkg-0/src/component-0/view.mojo"
    ):
        raise Error("fair corpus first candidate changed")


def _sort_timings(mut values: List[Int]):
    # Thirty-one samples make this benchmark-only insertion sort negligible.
    for index in range(1, len(values)):
        var value = values[index]
        var destination = index
        while destination > 0 and values[destination - 1] > value:
            values[destination] = values[destination - 1]
            destination -= 1
        values[destination] = value


def _report(
    operation: StringSlice,
    case_name: StringSlice,
    candidate_count: Int,
    scanned_count: Int,
    var timings: List[Int],
):
    _sort_timings(timings)
    # Nearest-rank percentiles: ranks 16 and 30 for 31 sorted samples.
    var p50 = timings[15]
    var p95 = timings[29]
    print(
        "FAIR implementation=yuragi operation=",
        operation,
        " case=",
        case_name,
        " candidates=",
        candidate_count,
        " scanned=",
        scanned_count,
        " samples=31 statistic=nearest-rank p50_ns=",
        p50,
        " p95_ns=",
        p95,
        sep="",
    )


def _benchmark_candidate_materialization(count: Int, expected_bytes: Int) raises:
    var warmup = _candidates(count)
    keep(len(warmup))
    _validate_corpus(warmup, expected_bytes)
    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var started = perf_counter_ns()
        var candidates = _candidates(count)
        var elapsed = perf_counter_ns() - started
        keep(len(candidates))
        _validate_corpus(candidates, expected_bytes)
        timings.append(elapsed)
    _report("candidate_materialize", "plain_ascii", count, 0, timings^)


def _benchmark_full_search(
    mut index: SearchIndex,
    query: StringSlice,
    reset_query: StringSlice,
    case_name: StringSlice,
    expected_total: Int,
) raises:
    _ = index.search(reset_query, CaseMode.SMART_ASCII, 20)
    var warmup = index.search(query, CaseMode.SMART_ASCII, 20)
    if warmup.total_matches != expected_total:
        raise Error(
            "fair benchmark total changed for ",
            case_name,
            "; expected ",
            expected_total,
            ", got ",
            warmup.total_matches,
        )
    if index.last_scanned_count() != len(index):
        raise Error("fair full-search setup did not scan the complete index")
    keep(warmup.total_matches + len(warmup.rows) + index.last_scanned_count())

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        _ = index.search(reset_query, CaseMode.SMART_ASCII, 20)
        var started = perf_counter_ns()
        var page = index.search(query, CaseMode.SMART_ASCII, 20)
        var elapsed = perf_counter_ns() - started
        if page.total_matches != expected_total or index.last_scanned_count() != len(
            index
        ):
            raise Error("fair benchmark result changed during measurement")
        keep(page.total_matches + len(page.rows) + index.last_scanned_count())
        timings.append(elapsed)
    _report("full_search", case_name, len(index), len(index), timings^)


def _benchmark_repeated_query(
    mut index: SearchIndex,
    query: StringSlice,
    case_name: StringSlice,
    expected_total: Int,
) raises:
    _ = index.search("!", CaseMode.SMART_ASCII, 20)
    var initial = index.search(query, CaseMode.SMART_ASCII, 20)
    if initial.total_matches != expected_total:
        raise Error("fair repeated-query setup returned an unexpected total")

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var started = perf_counter_ns()
        var repeated = index.search(query, CaseMode.SMART_ASCII, 20)
        var elapsed = perf_counter_ns() - started
        if (
            repeated.total_matches != expected_total
            or index.last_scanned_count() != expected_total
        ):
            raise Error("fair repeated-query scan set changed")
        keep(repeated.total_matches + len(repeated.rows) + index.last_scanned_count())
        timings.append(elapsed)
    _report(
        "repeated_query",
        case_name,
        len(index),
        expected_total,
        timings^,
    )


def _benchmark_extension(
    mut index: SearchIndex,
    expected_base_total: Int,
    expected_extended_total: Int,
) raises:
    _ = index.search("!", CaseMode.SMART_ASCII, 20)
    var warm_base = index.search("component1", CaseMode.SMART_ASCII, 20)
    var warm_extended = index.search("component100", CaseMode.SMART_ASCII, 20)
    if (
        warm_base.total_matches != expected_base_total
        or warm_extended.total_matches != expected_extended_total
    ):
        raise Error("fair extension corpus match totals changed")
    keep(warm_base.total_matches + warm_extended.total_matches)

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        # The shorter base does not extend the previous longer query, so this
        # setup is a full scan. Only the extension itself is timed.
        var base = index.search("component1", CaseMode.SMART_ASCII, 20)
        var started = perf_counter_ns()
        var extended = index.search("component100", CaseMode.SMART_ASCII, 20)
        var elapsed = perf_counter_ns() - started
        if (
            base.total_matches != expected_base_total
            or extended.total_matches != expected_extended_total
            or index.last_scanned_count() != expected_base_total
        ):
            raise Error("fair incremental extension scan set changed")
        keep(base.total_matches + extended.total_matches + index.last_scanned_count())
        timings.append(elapsed)
    _report(
        "incremental_extension",
        "extend_component1_to_component100",
        len(index),
        expected_base_total,
        timings^,
    )


def _run(count: Int, expected_bytes: Int) raises:
    _benchmark_candidate_materialization(count, expected_bytes)
    var candidates = _candidates(count)
    _validate_corpus(candidates, expected_bytes)
    var index = SearchIndex(candidates^)
    _benchmark_full_search(
        index,
        "pkgsrcview",
        "zzzzzzzz",
        "all_hit_pkgsrcview",
        count,
    )
    _benchmark_full_search(
        index,
        "zzzzzzzz",
        "pkgsrcview",
        "no_hit_zzzzzzzz",
        0,
    )
    var base_total = 3_439 if count == 10_000 else 40_951
    var extended_total = 37 if count == 10_000 else 856
    _benchmark_full_search(
        index,
        "component1",
        "zzzzzzzz",
        "full_component1",
        base_total,
    )
    _benchmark_full_search(
        index,
        "component100",
        "zzzzzzzz",
        "full_component100",
        extended_total,
    )
    _benchmark_repeated_query(
        index,
        "component1",
        "repeat_component1",
        base_total,
    )
    _benchmark_extension(index, base_total, extended_total)


def main() raises:
    print(
        "FAIR_HEADER protocol=plain-search-v1 implementation=yuragi ",
        "limit=20 samples=31 warmup=1 memory=not-measured",
        sep="",
    )
    _run(10_000, 447_851)
    _run(100_000, 4_578_580)
