"""Persistent exact search state for interactive query refinement."""

from hibana import CaseMode, Matcher, Scheme, TopK
from std.collections import List

from yuragi.candidate import Candidate
from yuragi.ranking import RankedCandidate, SearchPage


struct SearchIndex(Copyable, Sized):
    """Own candidates and reuse the exact previous match set.

    Non-empty query extensions and identical queries can only retain or remove
    matches, so they scan the previous complete match-index list. Empty identity
    state is implicit and a following non-empty query scans the corpus.
    Backspace, arbitrary edits, or case-mode changes also perform a full scan.
    The current implementation deliberately preserves Hibana's exact ranking
    semantics; prepared and hybrid scorers can replace the private scan without
    changing this API.
    """

    var _candidates: List[Candidate]
    var _matching_indices: List[Int]
    var _next_matching_indices: List[Int]
    var _previous_query: String
    var _previous_case_mode: CaseMode
    var _has_previous: Bool
    var _previous_was_identity: Bool
    var _last_scanned_count: Int
    var _last_incremental: Bool

    def __init__(out self, var candidates: List[Candidate]):
        self._candidates = candidates^
        self._matching_indices = List[Int]()
        self._next_matching_indices = List[Int]()
        self._previous_query = String()
        self._previous_case_mode = CaseMode.SMART_ASCII
        self._has_previous = False
        self._previous_was_identity = False
        self._last_scanned_count = 0
        self._last_incremental = False

    def __len__(self) -> Int:
        return len(self._candidates)

    def source_index_at(self, index: Int) -> Int:
        """Return one candidate's stable input identity."""
        debug_assert(index >= 0 and index < len(self._candidates))
        return self._candidates[index].source_index

    def copy_candidate_at(self, index: Int) -> Candidate:
        """Copy one candidate for accepted-output ownership."""
        debug_assert(index >= 0 and index < len(self._candidates))
        ref candidate = self._candidates[index]
        return Candidate(candidate.source_index, String(candidate.text))

    def last_scanned_count(self) -> Int:
        """Return how many candidates reached the matcher in the last search."""
        return self._last_scanned_count

    def last_search_was_incremental(self) -> Bool:
        """Return whether the last search reused the prior complete match set."""
        return self._last_incremental

    def _can_refine(self, query: StringSlice, case_mode: CaseMode) -> Bool:
        if not self._has_previous or case_mode != self._previous_case_mode:
            return False
        return query.startswith(self._previous_query)

    def _remember_query(mut self, query: StringSlice, case_mode: CaseMode):
        self._previous_query = String(query)
        self._previous_case_mode = case_mode
        self._has_previous = True
        self._previous_was_identity = query == ""

    def _replace_matches(mut self):
        swap(self._matching_indices, self._next_matching_indices)

    def _identity_page(
        mut self, query: StringSlice, case_mode: CaseMode, k: Int
    ) raises -> SearchPage:
        if len(self._candidates) == 0:
            self._matching_indices.clear()
            self._next_matching_indices.clear()
            self._last_scanned_count = 0
            self._last_incremental = self._can_refine(query, case_mode)
            self._remember_query(query, case_mode)
            return SearchPage()
        # Identity is represented by the corpus itself. Retaining a second
        # `[0..N)` integer list would add O(N) time and memory while conveying
        # no information. A following non-empty query performs a full scan.
        self._matching_indices.clear()
        self._next_matching_indices.clear()
        var row_count = min(k, len(self._candidates))
        var rows = List[RankedCandidate](capacity=row_count)
        for index in range(row_count):
            ref candidate = self._candidates[index]
            rows.append(
                RankedCandidate(
                    candidate.source_index,
                    String(candidate.text),
                    0,
                    List[Int](),
                )
            )
        var page = SearchPage(rows^, len(self._candidates))
        self._last_scanned_count = 0
        self._last_incremental = self._can_refine(query, case_mode)
        self._remember_query(query, case_mode)
        return page^

    def _push_match(
        mut self,
        matcher: Matcher,
        mut top_k: TopK,
        candidate_index: Int,
    ):
        var result = matcher.match(self._candidates[candidate_index].text)
        self._last_scanned_count += 1
        if result.matched:
            self._next_matching_indices.append(candidate_index)
        top_k.push(candidate_index, result^)

    def search(
        mut self,
        query: StringSlice,
        case_mode: CaseMode = CaseMode.SMART_ASCII,
        k: Int = 20,
    ) raises -> SearchPage:
        """Return exact bounded rows and retain the full match set for refinement."""
        if k < 1:
            raise Error(String("search index requires k >= 1, got ", k))
        if query == "":
            return self._identity_page(query, case_mode, k)
        if len(self._candidates) == 0:
            self._matching_indices.clear()
            self._next_matching_indices.clear()
            self._last_scanned_count = 0
            self._last_incremental = self._can_refine(query, case_mode)
            self._remember_query(query, case_mode)
            return SearchPage()

        var incremental = self._can_refine(query, case_mode) and not (
            self._previous_was_identity
        )
        var matcher = Matcher(query, case_mode=case_mode, scheme=Scheme.DEFAULT)
        var top_k = TopK(k)
        self._next_matching_indices.clear()
        self._last_scanned_count = 0

        if incremental:
            for previous_index in range(len(self._matching_indices)):
                self._push_match(
                    matcher,
                    top_k,
                    self._matching_indices[previous_index],
                )
        else:
            for candidate_index in range(len(self._candidates)):
                self._push_match(matcher, top_k, candidate_index)

        var total_matches = len(self._next_matching_indices)
        var ranked = top_k^.take_ranked()
        var rows = List[RankedCandidate](capacity=len(ranked))
        for index in range(len(ranked)):
            ref candidate = self._candidates[ranked[index].index]
            rows.append(
                RankedCandidate(
                    candidate.source_index,
                    String(candidate.text),
                    ranked[index].score,
                    ranked[index].positions.copy(),
                )
            )

        var page = SearchPage(rows^, total_matches)
        self._replace_matches()
        self._last_incremental = incremental
        self._remember_query(query, case_mode)
        return page^
