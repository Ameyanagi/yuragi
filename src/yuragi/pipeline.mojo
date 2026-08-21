"""Shared application orchestration for filtering and interactive ranking."""

from hibana import Matcher, Scheme
from std.collections import List

from yuragi.candidate import Candidate
from yuragi.options import Options
from yuragi.ranking import RankedCandidate, rank_candidates


def matching_backend_required(options: Options) -> Bool:
    """Return whether the invocation needs ecosystem matching libraries."""
    return options.has_filter and options.query != ""


def validate_foundation_mode(options: Options) raises:
    """Reject invalid report combinations and unavailable phonetic modes."""
    if options.explain and not options.has_filter:
        raise Error("--explain is a filter-mode report and requires --filter QUERY")
    if options.explain and options.print0:
        raise Error(
            "--explain writes a line-oriented report and conflicts with --print0"
        )
    if options.explain and options.query == "":
        raise Error(
            "--explain requires a non-empty --filter query; an empty query "
            "performs no matching"
        )
    if (
        (not options.has_filter or matching_backend_required(options))
        and options.has_language
        and options.language != "auto"
    ):
        raise Error(
            "--lang ",
            options.language,
            (
                " phonetic matching awaits the Yomi integration; direct matching "
                "works without --lang"
            ),
        )


def rank_query(
    candidates: Span[Candidate, _], query: StringSlice, options: Options
) raises -> List[RankedCandidate]:
    """Match and boundedly rank one query through the shared Hibana pipeline."""
    var matcher = Matcher(
        query,
        case_mode=options.case_mode,
        scheme=Scheme.DEFAULT,
    )
    var k = options.limit if options.has_limit else len(candidates)
    return rank_candidates(candidates, matcher, k)


def select_ranked(
    candidates: Span[Candidate, _], options: Options
) raises -> List[RankedCandidate]:
    """Match and boundedly rank candidates with one prepared matcher."""
    return rank_query(candidates, options.query, options)


def _select_validated(
    var candidates: List[Candidate], options: Options
) raises -> List[Candidate]:
    """Apply empty-query or ranked selection after mode validation."""
    if options.query == "":
        if not options.has_limit or options.limit >= len(candidates):
            return candidates^
        var limited = List[Candidate](capacity=options.limit)
        for index in range(options.limit):
            limited.append(
                Candidate(
                    candidates[index].source_index,
                    String(candidates[index].text),
                )
            )
        return limited^

    var ranked = select_ranked(candidates, options)
    var selected = List[Candidate](capacity=len(ranked))
    for index in range(len(ranked)):
        selected.append(
            Candidate(
                ranked[index].source_index,
                String(ranked[index].text),
            )
        )
    return selected^


def select(var candidates: List[Candidate], options: Options) raises -> List[Candidate]:
    """Apply validated empty-query or ranked noninteractive selection."""
    validate_foundation_mode(options)
    return _select_validated(candidates^, options)
