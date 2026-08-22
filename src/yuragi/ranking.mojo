"""Yuragi-owned candidate values and bounded Hibana ranking orchestration."""

from hibana import Matcher, TopK
from std.collections import List

from yuragi.candidate import Candidate


struct RankedCandidate(Copyable, Equatable):
    """One selected candidate with its Hibana score and scalar positions."""

    var source_index: Int
    var text: String
    var score: Int
    var positions: List[Int]

    def __init__(
        out self,
        source_index: Int,
        var text: String,
        score: Int,
        var positions: List[Int],
    ):
        """Create a ranked value from owned candidate text and positions."""
        self.source_index = source_index
        self.text = text^
        self.score = score
        self.positions = positions^

    def __eq__(self, other: Self) -> Bool:
        """Return whether every public ranked-candidate field is equal."""
        if (
            self.source_index != other.source_index
            or self.text != other.text
            or self.score != other.score
            or len(self.positions) != len(other.positions)
        ):
            return False
        for index in range(len(self.positions)):
            if self.positions[index] != other.positions[index]:
                return False
        return True


struct SearchPage(Copyable, Equatable):
    """Bounded ranked rows plus the untruncated number of matches.

    ``rows`` contains at most the requested result limit. ``total_matches``
    counts every matching candidate before that limit is applied, so picker
    automation and counters never infer cardinality from a truncated page.
    """

    var rows: List[RankedCandidate]
    var total_matches: Int

    def __init__(out self):
        self.rows = List[RankedCandidate]()
        self.total_matches = 0

    def __init__(out self, var rows: List[RankedCandidate], total_matches: Int) raises:
        if total_matches < len(rows):
            raise Error(
                "search total_matches must be at least the retained row count; got ",
                total_matches,
                " total matches and ",
                len(rows),
                " rows",
            )
        self.rows = rows^
        self.total_matches = total_matches

    def __eq__(self, other: Self) -> Bool:
        if self.total_matches != other.total_matches or len(self.rows) != len(
            other.rows
        ):
            return False
        for index in range(len(self.rows)):
            if self.rows[index] != other.rows[index]:
                return False
        return True

    def take_rows(var self) -> List[RankedCandidate]:
        """Consume this page and return its retained rows without copying."""
        var result = List[RankedCandidate]()
        swap(result, self.rows)
        return result^


def rank_candidates_page(
    candidates: Span[Candidate, _], matcher: Matcher, k: Int
) raises -> SearchPage:
    """Return bounded rows while counting matches before truncation."""
    if len(candidates) == 0:
        return SearchPage()

    var top_k = TopK(k)
    var total_matches = 0
    for index in range(len(candidates)):
        var result = matcher.match(candidates[index].text)
        if result.matched:
            total_matches += 1
        top_k.push(index, result^)

    var ranked = top_k^.take_ranked()
    var rows = List[RankedCandidate](capacity=len(ranked))
    for index in range(len(ranked)):
        ref candidate = candidates[ranked[index].index]
        rows.append(
            RankedCandidate(
                candidate.source_index,
                String(candidate.text),
                ranked[index].score,
                ranked[index].positions.copy(),
            )
        )
    return SearchPage(rows^, total_matches)


def rank_candidates(
    candidates: Span[Candidate, _], matcher: Matcher, k: Int
) raises -> List[RankedCandidate]:
    """Boundedly retain matches and attach their candidate values.

    Results are ordered by score descending, then source order ascending;
    equal-score results preserve input order.
    """
    var page = rank_candidates_page(candidates, matcher, k)
    return page^.take_rows()
