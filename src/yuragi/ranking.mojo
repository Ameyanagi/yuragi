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


def rank_candidates(
    candidates: Span[Candidate, _], matcher: Matcher, k: Int
) raises -> List[RankedCandidate]:
    """Boundedly retain matches and attach their candidate values.

    Results are ordered by score descending, then source order ascending;
    equal-score results preserve input order.
    """
    if len(candidates) == 0:
        return List[RankedCandidate]()

    var top_k = TopK(k)
    for index in range(len(candidates)):
        var result = matcher.match(candidates[index].text)
        top_k.push(index, result^)

    var ranked = top_k^.take_ranked()
    var results = List[RankedCandidate](capacity=len(ranked))
    for index in range(len(ranked)):
        ref candidate = candidates[ranked[index].index]
        results.append(
            RankedCandidate(
                candidate.source_index,
                String(candidate.text),
                ranked[index].score,
                ranked[index].positions.copy(),
            )
        )
    return results^
