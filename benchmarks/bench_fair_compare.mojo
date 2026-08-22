"""Fair, deterministic Yuru/Yuragi plain-search comparison protocol."""

from hibana import CaseMode
from std.benchmark import keep
from std.collections import List
from std.time import perf_counter_ns

from yuragi.candidate import Candidate
from yuragi.ranking import SearchPage
from yuragi.search_index import SearchIndex


comptime _WARMUPS = 3
comptime _SAMPLES = 31
comptime _LIMIT = 20
comptime _CHECKSUM_MODULUS = 1_000_000_007


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


def _expected_corpus_checksum(count: Int) raises -> Int:
    """Return the locked plain-search-v1 ordered-corpus checksum."""
    if count == 10_000:
        return 830_579_830
    if count == 100_000:
        return 113_956_248
    raise Error("unsupported plain-search-v1 corpus cardinality")


def _expected_result_checksum(case_name: StringSlice, count: Int) raises -> Int:
    """Return the locked Yuragi result checksum for one protocol case."""
    if count == 10_000:
        if case_name == "all_hit_pkgsrcview":
            return 10_000_388_532
        if case_name == "no_hit_zzzzzzzz":
            return 0
        if case_name == "full_component1" or case_name == "repeat_component1":
            return 3_439_606_180
        if case_name == "full_component100" or case_name == "incremental_extension":
            return 37_932_027
    elif count == 100_000:
        if case_name == "all_hit_pkgsrcview":
            return 100_000_658_532
        if case_name == "no_hit_zzzzzzzz":
            return 0
        if case_name == "full_component1" or case_name == "repeat_component1":
            return 40_951_718_716
        if case_name == "full_component100" or case_name == "incremental_extension":
            return 859_221_034
    raise Error("unsupported plain-search-v1 result checksum case")


def _corpus_checksum(candidates: Span[Candidate, _]) -> Int:
    """Hash ordered identities and UTF-8 bytes with a portable recurrence."""
    var checksum = 17
    for candidate_index in range(len(candidates)):
        ref candidate = candidates[candidate_index]
        checksum = (checksum * 131 + candidate.source_index + 1) % _CHECKSUM_MODULUS
        var bytes = candidate.text.as_bytes()
        checksum = (checksum * 131 + len(bytes)) % _CHECKSUM_MODULUS
        for byte_index in range(len(bytes)):
            checksum = (checksum * 131 + Int(bytes[byte_index])) % _CHECKSUM_MODULUS
        # Keep candidate boundaries observable even if adjacent text changes.
        checksum = (checksum * 131 + 257) % _CHECKSUM_MODULUS
    return checksum


def _validate_corpus(
    candidates: Span[Candidate, _],
    expected_bytes: Int,
    expected_checksum: Int,
) raises -> Int:
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
    var checksum = _corpus_checksum(candidates)
    if checksum != expected_checksum:
        raise Error(
            "fair corpus checksum changed; expected ",
            expected_checksum,
            ", got ",
            checksum,
        )
    return checksum


def _result_checksum(page: SearchPage) -> Int:
    """Hash exact cardinality and ordered retained result semantics."""
    var checksum = page.total_matches * 1_000_003 + len(page.rows) * 97
    for row_index in range(len(page.rows)):
        ref row = page.rows[row_index]
        checksum += (row_index + 17) * (row.source_index + 1)
        checksum += row.score * (row_index + 1)
        for position_index in range(len(row.positions)):
            checksum += (position_index + 3) * (row.positions[position_index] + 1)
    return checksum


def _validate_result(
    case_name: StringSlice,
    page: SearchPage,
    expected_total: Int,
    expected_checksum: Int,
) raises -> Int:
    if page.total_matches != expected_total:
        raise Error(
            "fair result cardinality changed for ",
            case_name,
            "; expected ",
            expected_total,
            ", got ",
            page.total_matches,
        )
    if len(page.rows) != min(_LIMIT, expected_total):
        raise Error("fair retained result cardinality changed for ", case_name)
    var checksum = _result_checksum(page)
    if checksum != expected_checksum:
        raise Error(
            "fair result checksum changed for ",
            case_name,
            "; expected ",
            expected_checksum,
            ", got ",
            checksum,
        )
    return checksum


def _preflight_full_case(
    mut index: SearchIndex,
    query: StringSlice,
    reset_query: StringSlice,
    case_name: StringSlice,
    expected_total: Int,
    expected_checksum: Int,
) raises:
    _ = index.search(reset_query, CaseMode.SMART_ASCII, _LIMIT)
    var page = index.search(query, CaseMode.SMART_ASCII, _LIMIT)
    keep(_validate_result(case_name, page, expected_total, expected_checksum))
    if index.last_scanned_count() != len(index):
        raise Error("plain-search-v1 preflight did not perform a full scan")


def _preflight_results(
    mut index: SearchIndex,
    base_total: Int,
    extended_total: Int,
) raises:
    """Assert every locked semantic result before any measured operation."""
    var count = len(index)
    _preflight_full_case(
        index,
        "pkgsrcview",
        "zzzzzzzz",
        "all_hit_pkgsrcview",
        count,
        _expected_result_checksum("all_hit_pkgsrcview", count),
    )
    _preflight_full_case(
        index,
        "zzzzzzzz",
        "pkgsrcview",
        "no_hit_zzzzzzzz",
        0,
        _expected_result_checksum("no_hit_zzzzzzzz", count),
    )
    _preflight_full_case(
        index,
        "component1",
        "zzzzzzzz",
        "full_component1",
        base_total,
        _expected_result_checksum("full_component1", count),
    )
    _preflight_full_case(
        index,
        "component100",
        "zzzzzzzz",
        "full_component100",
        extended_total,
        _expected_result_checksum("full_component100", count),
    )

    _ = index.search("!", CaseMode.SMART_ASCII, _LIMIT)
    _ = index.search("component1", CaseMode.SMART_ASCII, _LIMIT)
    var repeated = index.search("component1", CaseMode.SMART_ASCII, _LIMIT)
    keep(
        _validate_result(
            "repeat_component1",
            repeated,
            base_total,
            _expected_result_checksum("repeat_component1", count),
        )
    )
    if index.last_scanned_count() != base_total:
        raise Error("plain-search-v1 repeated-query preflight scan set changed")

    _ = index.search("!", CaseMode.SMART_ASCII, _LIMIT)
    _ = index.search("component1", CaseMode.SMART_ASCII, _LIMIT)
    var extended = index.search("component100", CaseMode.SMART_ASCII, _LIMIT)
    keep(
        _validate_result(
            "incremental_extension",
            extended,
            extended_total,
            _expected_result_checksum("incremental_extension", count),
        )
    )
    if index.last_scanned_count() != base_total:
        raise Error("plain-search-v1 extension preflight scan set changed")


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
    cardinality: Int,
    checksum: Int,
    var timings: List[Int],
):
    _sort_timings(timings)
    # Nearest-rank percentiles: ranks 16 and 30 for 31 sorted samples.
    var p50 = timings[15]
    var p95 = timings[29]
    print(
        "FAIR protocol=plain-search-v1 implementation=yuragi operation=",
        operation,
        " case=",
        case_name,
        " candidates=",
        candidate_count,
        " scanned=",
        scanned_count,
        " cardinality=",
        cardinality,
        " semantic_checksum=",
        checksum,
        " warmups=3 samples=31 statistic=nearest-rank p50_ns=",
        p50,
        " p95_ns=",
        p95,
        sep="",
    )


def _benchmark_candidate_materialization(
    count: Int, expected_bytes: Int, expected_checksum: Int
) raises:
    for _ in range(_WARMUPS):
        var warmup = _candidates(count)
        keep(_validate_corpus(warmup, expected_bytes, expected_checksum))
    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var started = perf_counter_ns()
        var candidates = _candidates(count)
        var elapsed = perf_counter_ns() - started
        keep(_validate_corpus(candidates, expected_bytes, expected_checksum))
        timings.append(elapsed)
    _report(
        "candidate_materialize",
        "plain_ascii",
        count,
        0,
        count,
        expected_checksum,
        timings^,
    )


def _benchmark_full_search(
    mut index: SearchIndex,
    query: StringSlice,
    reset_query: StringSlice,
    case_name: StringSlice,
    expected_total: Int,
    expected_checksum: Int,
) raises:
    var semantic_checksum = 0
    for _ in range(_WARMUPS):
        _ = index.search(reset_query, CaseMode.SMART_ASCII, _LIMIT)
        var warmup = index.search(query, CaseMode.SMART_ASCII, _LIMIT)
        semantic_checksum = _validate_result(
            case_name, warmup, expected_total, expected_checksum
        )
        if index.last_scanned_count() != len(index):
            raise Error("fair full-search setup did not scan the complete index")
        keep(semantic_checksum + index.last_scanned_count())

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        _ = index.search(reset_query, CaseMode.SMART_ASCII, _LIMIT)
        var started = perf_counter_ns()
        var page = index.search(query, CaseMode.SMART_ASCII, _LIMIT)
        var elapsed = perf_counter_ns() - started
        semantic_checksum = _validate_result(
            case_name, page, expected_total, expected_checksum
        )
        if index.last_scanned_count() != len(index):
            raise Error("fair benchmark result changed during measurement")
        keep(semantic_checksum + index.last_scanned_count())
        timings.append(elapsed)
    _report(
        "full_search",
        case_name,
        len(index),
        len(index),
        expected_total,
        semantic_checksum,
        timings^,
    )


def _benchmark_repeated_query(
    mut index: SearchIndex,
    query: StringSlice,
    case_name: StringSlice,
    expected_total: Int,
    expected_checksum: Int,
) raises:
    _ = index.search("!", CaseMode.SMART_ASCII, _LIMIT)
    var initial = index.search(query, CaseMode.SMART_ASCII, _LIMIT)
    var semantic_checksum = _validate_result(
        case_name, initial, expected_total, expected_checksum
    )
    for _ in range(_WARMUPS):
        var warmup = index.search(query, CaseMode.SMART_ASCII, _LIMIT)
        semantic_checksum = _validate_result(
            case_name, warmup, expected_total, expected_checksum
        )
        if index.last_scanned_count() != expected_total:
            raise Error("fair repeated-query warmup scan set changed")
        keep(semantic_checksum + index.last_scanned_count())

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        var started = perf_counter_ns()
        var repeated = index.search(query, CaseMode.SMART_ASCII, _LIMIT)
        var elapsed = perf_counter_ns() - started
        semantic_checksum = _validate_result(
            case_name, repeated, expected_total, expected_checksum
        )
        if index.last_scanned_count() != expected_total:
            raise Error("fair repeated-query scan set changed")
        keep(semantic_checksum + index.last_scanned_count())
        timings.append(elapsed)
    _report(
        "repeated_query",
        case_name,
        len(index),
        expected_total,
        expected_total,
        semantic_checksum,
        timings^,
    )


def _benchmark_extension(
    mut index: SearchIndex,
    expected_base_total: Int,
    expected_extended_total: Int,
    expected_base_checksum: Int,
    expected_extended_checksum: Int,
) raises:
    _ = index.search("!", CaseMode.SMART_ASCII, _LIMIT)
    var semantic_checksum = 0
    for _ in range(_WARMUPS):
        var warm_base = index.search("component1", CaseMode.SMART_ASCII, _LIMIT)
        _ = _validate_result(
            "full_component1",
            warm_base,
            expected_base_total,
            expected_base_checksum,
        )
        var warm_extended = index.search("component100", CaseMode.SMART_ASCII, _LIMIT)
        semantic_checksum = _validate_result(
            "incremental_extension",
            warm_extended,
            expected_extended_total,
            expected_extended_checksum,
        )
        if index.last_scanned_count() != expected_base_total:
            raise Error("fair incremental extension warmup scan set changed")
        keep(semantic_checksum + index.last_scanned_count())

    var timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        # The shorter base does not extend the previous longer query, so this
        # setup is a full scan. Only the extension itself is timed.
        var base = index.search("component1", CaseMode.SMART_ASCII, _LIMIT)
        var started = perf_counter_ns()
        var extended = index.search("component100", CaseMode.SMART_ASCII, _LIMIT)
        var elapsed = perf_counter_ns() - started
        _ = _validate_result(
            "full_component1",
            base,
            expected_base_total,
            expected_base_checksum,
        )
        semantic_checksum = _validate_result(
            "incremental_extension",
            extended,
            expected_extended_total,
            expected_extended_checksum,
        )
        if index.last_scanned_count() != expected_base_total:
            raise Error("fair incremental extension scan set changed")
        keep(semantic_checksum + index.last_scanned_count())
        timings.append(elapsed)
    _report(
        "incremental_extension",
        "extend_component1_to_component100",
        len(index),
        expected_base_total,
        expected_extended_total,
        semantic_checksum,
        timings^,
    )


def _run(count: Int, expected_bytes: Int) raises:
    var candidates = _candidates(count)
    var corpus_checksum = _expected_corpus_checksum(count)
    keep(_validate_corpus(candidates, expected_bytes, corpus_checksum))
    var base_total = 3_439 if count == 10_000 else 40_951
    var extended_total = 37 if count == 10_000 else 856
    var index = SearchIndex(candidates^)
    _preflight_results(index, base_total, extended_total)

    _benchmark_candidate_materialization(count, expected_bytes, corpus_checksum)
    _benchmark_full_search(
        index,
        "pkgsrcview",
        "zzzzzzzz",
        "all_hit_pkgsrcview",
        count,
        _expected_result_checksum("all_hit_pkgsrcview", count),
    )
    _benchmark_full_search(
        index,
        "zzzzzzzz",
        "pkgsrcview",
        "no_hit_zzzzzzzz",
        0,
        _expected_result_checksum("no_hit_zzzzzzzz", count),
    )
    _benchmark_full_search(
        index,
        "component1",
        "zzzzzzzz",
        "full_component1",
        base_total,
        _expected_result_checksum("full_component1", count),
    )
    _benchmark_full_search(
        index,
        "component100",
        "zzzzzzzz",
        "full_component100",
        extended_total,
        _expected_result_checksum("full_component100", count),
    )
    _benchmark_repeated_query(
        index,
        "component1",
        "repeat_component1",
        base_total,
        _expected_result_checksum("repeat_component1", count),
    )
    _benchmark_extension(
        index,
        base_total,
        extended_total,
        _expected_result_checksum("full_component1", count),
        _expected_result_checksum("incremental_extension", count),
    )


def main() raises:
    print(
        "FAIR_HEADER protocol=plain-search-v1 implementation=yuragi ",
        "mojo=1.0.0 limit=20 warmups=3 samples=31 memory=not-measured",
        sep="",
    )
    _run(10_000, 447_851)
    _run(100_000, 4_578_580)
