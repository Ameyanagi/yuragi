"""Shared application orchestration for filtering and interactive ranking."""

from hibana import Matcher, Scheme
from std.collections import List

from yuragi.candidate import Candidate
from yuragi.options import Options
from yuragi.ranking import RankedCandidate, rank_candidates


struct InitialAutomationAction(Copyable, Equatable, ImplicitlyCopyable):
    """Nominal action chosen from the initial interactive match set."""

    var _value: Int

    comptime CONTINUE = InitialAutomationAction(_value=0)
    comptime ACCEPT = InitialAutomationAction(_value=1)
    comptime EXIT_NO_MATCH = InitialAutomationAction(_value=2)

    def __init__(out self, *, _value: Int):
        self._value = _value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


struct InitialAutomationDecision(Copyable, Equatable):
    """Pure pre-TUI decision together with the exact initial picker rows."""

    var action: InitialAutomationAction
    var matches: List[RankedCandidate]

    def __init__(out self):
        self.action = InitialAutomationAction.CONTINUE
        self.matches = List[RankedCandidate]()

    def __init__(
        out self,
        action: InitialAutomationAction,
        var matches: List[RankedCandidate],
    ):
        self.action = action
        self.matches = matches^

    def __eq__(self, other: Self) -> Bool:
        if self.action != other.action or len(self.matches) != len(other.matches):
            return False
        for index in range(len(self.matches)):
            if self.matches[index] != other.matches[index]:
                return False
        return True

    def take_matches(var self) -> List[RankedCandidate]:
        """Consume the decision and return the initial picker rows."""
        var result = List[RankedCandidate]()
        swap(result, self.matches)
        return result^


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
    if options.has_language and options.language != "auto":
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


def _identity_rows(candidates: Span[Candidate, _]) -> List[RankedCandidate]:
    var rows = List[RankedCandidate](capacity=len(candidates))
    for index in range(len(candidates)):
        rows.append(
            RankedCandidate(
                candidates[index].source_index,
                String(candidates[index].text),
                0,
                List[Int](),
            )
        )
    return rows^


def rank_picker_query(
    candidates: Span[Candidate, _], query: StringSlice, options: Options
) raises -> List[RankedCandidate]:
    """Build picker rows, treating an empty query as all candidates."""
    if query == "":
        return _identity_rows(candidates)
    return rank_query(candidates, query, options)


def initial_automation(
    candidates: Span[Candidate, _], options: Options
) raises -> InitialAutomationDecision:
    """Evaluate interactive automation against the seeded initial ranking."""
    var matches = rank_picker_query(candidates, options.query, options)
    var action = InitialAutomationAction.CONTINUE
    if options.select_1 and len(matches) == 1:
        action = InitialAutomationAction.ACCEPT
    elif options.exit_0 and len(matches) == 0:
        action = InitialAutomationAction.EXIT_NO_MATCH
    return InitialAutomationDecision(action, matches^)


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
