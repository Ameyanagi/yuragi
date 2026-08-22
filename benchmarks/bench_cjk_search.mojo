"""Executable deterministic cjk-search-v1 preparation/search profile."""

from hibana import CaseMode
from std.benchmark import keep
from std.collections import List
from std.runtime.asyncrt import parallelism_level
from std.time import perf_counter_ns

from yuragi.candidate import Candidate
from yuragi.language import LanguageMode
from yuragi.phonetic import key_kind_name
from yuragi.ranking import SearchPage
from yuragi.search_index import SearchIndex


comptime _WARMUPS = 3
comptime _SAMPLES = 31
comptime _LIMIT = 20


struct _Case(Copyable):
    var name: String
    var language: LanguageMode
    var corpus: String
    var query: String

    def __init__(
        out self,
        name: StringSlice,
        language: LanguageMode,
        corpus: StringSlice,
        query: StringSlice,
    ):
        self.name = String(name)
        self.language = language
        self.corpus = String(corpus)
        self.query = String(query)


def _candidates(corpus: StringSlice, count: Int) -> List[Candidate]:
    var output = List[Candidate](capacity=count)
    for index in range(count):
        var text: String
        if corpus == "direct":
            text = String(
                "workspace/pkg-",
                index % 97,
                "/src/component-",
                index,
                "/view.mojo",
            )
        elif corpus == "zh":
            text = String("北京大学" if index % 10 == 0 else "上海站")
        elif corpus == "ja":
            text = String("カメラ" if index % 10 == 0 else "テレビ")
        else:
            text = String("한글" if index % 10 == 0 else "서울")
        output.append(Candidate(index, text^))
    return output^


def _byte_count(candidates: List[Candidate]) -> Int:
    var result = 0
    for index in range(len(candidates)):
        result += candidates[index].text.byte_length()
    return result


def _expected_bytes(corpus: StringSlice, count: Int) -> Int:
    if corpus == "direct":
        return 447_851 if count == 10_000 else 4_578_580
    if corpus == "zh":
        return 93_000 if count == 10_000 else 930_000
    if corpus == "ja":
        return 90_000 if count == 10_000 else 900_000
    return 60_000 if count == 10_000 else 600_000


def _sort_timings(mut values: List[Int]):
    for index in range(1, len(values)):
        var value = values[index]
        var destination = index
        while destination > 0 and values[destination - 1] > value:
            values[destination] = values[destination - 1]
            destination -= 1
        values[destination] = value


def _result_checksum(page: SearchPage) -> Int:
    """Order-sensitive sum over retained identity, score, and positions."""
    var checksum = page.total_matches * 1_000_003 + len(page.rows) * 97
    for row_index in range(len(page.rows)):
        ref row = page.rows[row_index]
        checksum += (row_index + 17) * (row.source_index + 1)
        checksum += row.score * (row_index + 1)
        for position_index in range(len(row.positions)):
            checksum += (position_index + 3) * (row.positions[position_index] + 1)
    return checksum


def _source_indices(page: SearchPage) -> String:
    var output = String()
    for index in range(len(page.rows)):
        if index > 0:
            output += ","
        output += String(page.rows[index].source_index)
    return output^


def _winning_key_kinds(page: SearchPage) -> String:
    var output = String()
    for index in range(len(page.rows)):
        if index > 0:
            output += ","
        output += key_kind_name(page.rows[index].key_kind)
    return output^


def _validate_page(benchmark_case: _Case, count: Int, page: SearchPage) raises:
    var expected_total = 0
    if (
        benchmark_case.name == "direct"
        or benchmark_case.name == "zh"
        or benchmark_case.name == "ja"
        or benchmark_case.name == "ko"
    ):
        expected_total = count if benchmark_case.name == "direct" else count // 10
    if page.total_matches != expected_total:
        raise Error(
            "cjk-search-v1 cardinality changed for ",
            benchmark_case.name,
            "; expected ",
            expected_total,
            ", got ",
            page.total_matches,
        )
    var expected_rows = min(_LIMIT, expected_total)
    if len(page.rows) != expected_rows:
        raise Error("cjk-search-v1 retained row count changed")
    for index in range(expected_rows):
        var expected_index = index
        if benchmark_case.name != "direct":
            expected_index = index * 10
        if benchmark_case.name == "direct" and index >= 10:
            expected_index = 87 + index if index < 13 else index - 3
        if page.rows[index].source_index != expected_index:
            raise Error(
                "cjk-search-v1 retained identity changed at row ",
                index,
                "; expected ",
                expected_index,
                ", got ",
                page.rows[index].source_index,
            )


def _prepare_sample(benchmark_case: _Case, count: Int) raises -> Int:
    var candidates = _candidates(benchmark_case.corpus, count)
    var actual_bytes = _byte_count(candidates)
    var expected_bytes = _expected_bytes(benchmark_case.corpus, count)
    if actual_bytes != expected_bytes:
        raise Error(
            "cjk-search-v1 corpus bytes changed; expected ",
            expected_bytes,
            ", got ",
            actual_bytes,
        )
    var started = perf_counter_ns()
    var index = SearchIndex(candidates^, benchmark_case.language)
    var elapsed = perf_counter_ns() - started
    keep(len(index) + index.prepared_key_count())
    return elapsed


def _run_case(benchmark_case: _Case, count: Int) raises:
    for _ in range(_WARMUPS):
        keep(_prepare_sample(benchmark_case, count))
    var preparation_timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        preparation_timings.append(_prepare_sample(benchmark_case, count))
    _sort_timings(preparation_timings)

    var candidates = _candidates(benchmark_case.corpus, count)
    var bytes = _byte_count(candidates)
    var index = SearchIndex(candidates^, benchmark_case.language)
    var preparation_checksum = (
        len(index) * 1_000_003 + index.prepared_key_count() * 97 + bytes
    )

    var last_page = SearchPage()
    for _ in range(_WARMUPS):
        _ = index.search("!reset!", CaseMode.SMART_ASCII, _LIMIT)
        last_page = index.search(benchmark_case.query, CaseMode.SMART_ASCII, _LIMIT)
        _validate_page(benchmark_case, count, last_page)

    var search_timings = List[Int](capacity=_SAMPLES)
    for _ in range(_SAMPLES):
        _ = index.search("!reset!", CaseMode.SMART_ASCII, _LIMIT)
        var started = perf_counter_ns()
        last_page = index.search(benchmark_case.query, CaseMode.SMART_ASCII, _LIMIT)
        var elapsed = perf_counter_ns() - started
        _validate_page(benchmark_case, count, last_page)
        if index.last_scanned_count() != count:
            raise Error("cjk-search-v1 search did not scan the full corpus")
        keep(_result_checksum(last_page))
        search_timings.append(elapsed)
    _sort_timings(search_timings)
    var coarse_parallel = (
        benchmark_case.language == LanguageMode.AUTO and count >= 4_096
    )
    var thread_count = min(
        max(parallelism_level(), 1), (count + 4_095) // 4_096
    ) if coarse_parallel else 1

    print(
        "CJK_SEARCH protocol=cjk-search-v1 mode=",
        benchmark_case.name,
        " corpus=",
        benchmark_case.corpus,
        " candidates=",
        count,
        " bytes=",
        bytes,
        " query=",
        benchmark_case.query,
        " limit=20 warmups=3 samples=31 statistic=nearest-rank",
        " preparation_p50_ms=",
        Float64(preparation_timings[15]) / 1_000_000.0,
        " preparation_p95_ms=",
        Float64(preparation_timings[29]) / 1_000_000.0,
        " search_p50_ms=",
        Float64(search_timings[15]) / 1_000_000.0,
        " search_p95_ms=",
        Float64(search_timings[29]) / 1_000_000.0,
        " preparation_checksum=",
        preparation_checksum,
        " result_checksum=",
        _result_checksum(last_page),
        " exact_matches=",
        last_page.total_matches,
        " retained_indices=",
        _source_indices(last_page),
        " winning_key_kinds=",
        _winning_key_kinds(last_page),
        " candidates_scanned=",
        index.last_scanned_count(),
        " compatible_pairs_scored=",
        index.last_scored_pair_count(),
        " positions_reconstructed=",
        index.last_position_reconstruction_count(),
        " threads=",
        thread_count,
        " coarse_parallel=",
        coarse_parallel,
        sep="",
    )


def main() raises:
    print(
        "CJK_SEARCH_HEADER protocol=cjk-search-v1 implementation=yuragi ",
        "mojo=1.0.0 limit=20 warmups=3 samples=31 available_threads=",
        max(parallelism_level(), 1),
        sep="",
    )
    var cases = [
        _Case("direct", LanguageMode.AUTO, "direct", "pkgsrcview"),
        _Case("auto-negative", LanguageMode.AUTO, "zh", "bjdx"),
        _Case("zh", LanguageMode.ZH, "zh", "bjdx"),
        _Case("ja", LanguageMode.JA, "ja", "kamera"),
        _Case("ko", LanguageMode.KO, "ko", "hangeul"),
    ]
    for count in [10_000, 100_000]:
        for case_index in range(len(cases)):
            _run_case(cases[case_index], count)
