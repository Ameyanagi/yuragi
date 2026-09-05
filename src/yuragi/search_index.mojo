"""Persistent, prepared CJK-aware search state."""

from hibana import CaseMode, MatchResult, Scheme, TopK
from hibana.fast import fast_score_at
from hibana.parallel import rank_corpus_exact
from hibana.prepared import MatchWorkspace, PreparedCorpus
from std.collections import List, Optional
from std.time import perf_counter_ns
from yomi import search_key_kinds_compatible

from yuragi.candidate import Candidate
from yuragi.language import LanguageMode
from yuragi.phonetic import (
    IndexedPhoneticKey,
    PreparedQueryKey,
    append_candidate_keys,
    candidate_representation_at,
    prepare_query_keys,
    project_key_positions,
)
from yuragi.ranking import RankedCandidate, SearchPage


struct _BestKeyMatch(Copyable, ImplicitlyCopyable):
    var matched: Bool
    var score: Int
    var key_index: Int
    var query_index: Int
    var scored_pairs: Int

    def __init__(
        out self,
        matched: Bool = False,
        score: Int = 0,
        key_index: Int = -1,
        query_index: Int = -1,
    ):
        self.matched = matched
        self.score = score
        self.key_index = key_index
        self.query_index = query_index
        self.scored_pairs = 0


struct SearchIndex(Sized):
    """Movably own candidates and a flattened, arena-backed key family.

    ``AUTO`` is deliberately direct-only. Explicit ``JA``, ``ZH``, and ``KO``
    modes prepare bounded Yomi key families once, then broad searches score the
    parallel Hibana corpus without constructing per-key position lists.
    Positions are reconstructed and projected to source text only for the
    final bounded rows.

    Direct query extensions retain the previous complete match set. Derived
    phonetic query families always scan the full candidate set because an
    extended input can change the family rather than merely narrow it.
    The index is intentionally not copyable: duplicating it would deep-copy
    candidate strings and prepared arenas. Transfer it with ``^`` instead.
    """

    var _candidates: List[Candidate]
    var _language: LanguageMode
    var _corpus: PreparedCorpus
    var _keys: List[IndexedPhoneticKey]
    var _candidate_key_offsets: List[Int]
    var _matching_indices: List[Int]
    var _next_matching_indices: List[Int]
    var _previous_query: String
    var _previous_case_mode: CaseMode
    var _has_previous: Bool
    var _previous_was_identity: Bool
    var _last_scanned_count: Int
    var _last_incremental: Bool
    var _last_scored_pair_count: Int
    var _last_position_reconstruction_count: Int

    def __init__(
        out self,
        var candidates: List[Candidate],
        language: LanguageMode = LanguageMode.AUTO,
    ) raises:
        language.validate()
        var corpus = PreparedCorpus(Scheme.DEFAULT)
        var keys = List[IndexedPhoneticKey]()
        var offsets = List[Int](capacity=len(candidates) + 1)
        offsets.append(0)
        for candidate_index in range(len(candidates)):
            append_candidate_keys(
                language,
                candidate_index,
                candidates[candidate_index].text,
                corpus,
                keys,
            )
            offsets.append(len(keys))

        self._candidates = candidates^
        self._language = language
        self._corpus = corpus^
        self._keys = keys^
        self._candidate_key_offsets = offsets^
        self._matching_indices = List[Int]()
        self._next_matching_indices = List[Int]()
        self._previous_query = String()
        self._previous_case_mode = CaseMode.SMART_ASCII
        self._has_previous = False
        self._previous_was_identity = False
        self._last_scanned_count = 0
        self._last_incremental = False
        self._last_scored_pair_count = 0
        self._last_position_reconstruction_count = 0

    def __len__(self) -> Int:
        return len(self._candidates)

    def language(self) -> LanguageMode:
        """Return this index's immutable key-family policy."""
        return self._language

    def prepared_key_count(self) -> Int:
        """Return the flattened key count for profiling and diagnostics."""
        return len(self._keys)

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
        """Return how many unique candidates reached the last broad scan."""
        return self._last_scanned_count

    def last_search_was_incremental(self) -> Bool:
        """Return whether direct search reused the prior complete match set."""
        return self._last_incremental

    def last_scored_pair_count(self) -> Int:
        """Return the compatible query/candidate key pairs scored last time."""
        return self._last_scored_pair_count

    def last_position_reconstruction_count(self) -> Int:
        """Return how many final candidate positions were reconstructed."""
        return self._last_position_reconstruction_count

    def _can_refine(self, query: StringSlice, case_mode: CaseMode) -> Bool:
        if self._language != LanguageMode.AUTO:
            return False
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
        mut self, query: StringSlice, case_mode: CaseMode, limit: Int
    ) raises -> SearchPage:
        if len(self._candidates) == 0:
            self._matching_indices.clear()
            self._next_matching_indices.clear()
            self._last_scanned_count = 0
            self._last_scored_pair_count = 0
            self._last_position_reconstruction_count = 0
            self._last_incremental = self._can_refine(query, case_mode)
            self._remember_query(query, case_mode)
            return SearchPage()
        # Identity is represented by the corpus itself. Retaining a second
        # [0..N) list would add O(N) memory and construction time.
        self._matching_indices.clear()
        self._next_matching_indices.clear()
        var row_count = min(limit, len(self._candidates))
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
        self._last_scored_pair_count = 0
        self._last_position_reconstruction_count = 0
        self._last_incremental = self._can_refine(query, case_mode)
        self._remember_query(query, case_mode)
        return page^

    def _best_key_match(
        mut self,
        candidate_index: Int,
        query_keys: List[PreparedQueryKey],
        mut workspace: MatchWorkspace,
        count_pairs: Bool = True,
    ) raises -> _BestKeyMatch:
        var best = _BestKeyMatch()
        var scored_pairs = 0
        var key_start = self._candidate_key_offsets[candidate_index]
        var key_end = self._candidate_key_offsets[candidate_index + 1]
        for key_index in range(key_start, key_end):
            ref key = self._keys[key_index]
            for query_index in range(len(query_keys)):
                ref query_key = query_keys[query_index]
                if not search_key_kinds_compatible(query_key.kind, key.kind):
                    continue
                scored_pairs += 1
                if count_pairs:
                    self._last_scored_pair_count += 1
                var result = workspace.score_at(
                    query_key.pattern, self._corpus, key_index
                )
                if not result.matched:
                    continue
                var weighted_score = result.score + key.weight + query_key.weight
                if (
                    not best.matched
                    or weighted_score > best.score
                    or (
                        weighted_score == best.score
                        and (
                            key_index < best.key_index
                            or (
                                key_index == best.key_index
                                and query_index < best.query_index
                            )
                        )
                    )
                ):
                    best = _BestKeyMatch(True, weighted_score, key_index, query_index)
        best.scored_pairs = scored_pairs
        return best

    def _scan_candidate(
        mut self,
        candidate_index: Int,
        query_keys: List[PreparedQueryKey],
        mut workspace: MatchWorkspace,
        mut top_k: TopK,
    ) raises:
        var best = self._best_key_match(candidate_index, query_keys, workspace)
        self._last_scanned_count += 1
        if not best.matched:
            return
        self._next_matching_indices.append(candidate_index)
        # The broad pass owns no position lists. TopK only retains O(limit)
        # empty lists; exact positions are reconstructed for those finalists.
        top_k.push(
            candidate_index,
            MatchResult(True, best.score, List[Int]()),
        )

    def _parallel_auto_search(
        mut self,
        query: StringSlice,
        case_mode: CaseMode,
        limit: Int,
        query_keys: List[PreparedQueryKey],
    ) raises -> SearchPage:
        """Use Hibana's exact coarse shards for a large direct full scan."""
        debug_assert(self._language == LanguageMode.AUTO)
        debug_assert(len(query_keys) == 1)
        var ranked_page = rank_corpus_exact(
            self._corpus,
            query_keys[0].pattern,
            limit,
        )

        # The parallel ranker intentionally retains only O(limit) identities.
        # A cheap linear membership pass reconstructs the complete set needed
        # for exact interactive query refinement; fast_score_at has exactly the
        # same membership relation as the exact matcher.
        self._next_matching_indices.clear()
        for candidate_index in range(len(self._candidates)):
            if fast_score_at(
                query_keys[0].pattern, self._corpus, candidate_index
            ).matched:
                self._next_matching_indices.append(candidate_index)
        debug_assert(len(self._next_matching_indices) == ranked_page.total_matches)

        var rows = List[RankedCandidate](capacity=len(ranked_page.rows))
        for row_index in range(len(ranked_page.rows)):
            ref ranked = ranked_page.rows[row_index]
            ref candidate = self._candidates[ranked.source_index]
            rows.append(
                RankedCandidate(
                    candidate.source_index,
                    String(candidate.text),
                    ranked.score,
                    ranked.positions.copy(),
                )
            )

        var page = SearchPage(rows^, ranked_page.total_matches)
        self._last_scanned_count = len(self._candidates)
        self._last_scored_pair_count = len(self._candidates)
        self._last_position_reconstruction_count = len(page.rows)
        self._replace_matches()
        self._last_incremental = False
        self._remember_query(query, case_mode)
        return page^

    def search(
        mut self,
        query: StringSlice,
        case_mode: CaseMode = CaseMode.SMART_ASCII,
        limit: Int = 20,
    ) raises -> SearchPage:
        """Return a bounded page and an exact unique-candidate match count."""
        if limit < 1:
            raise Error(String("search index requires limit >= 1, got ", limit))
        if query == "":
            return self._identity_page(query, case_mode, limit)
        if len(self._candidates) == 0:
            self._matching_indices.clear()
            self._next_matching_indices.clear()
            self._last_scanned_count = 0
            self._last_scored_pair_count = 0
            self._last_position_reconstruction_count = 0
            self._last_incremental = self._can_refine(query, case_mode)
            self._remember_query(query, case_mode)
            return SearchPage()

        # A public limit is a page bound, not permission to reserve that many
        # rows. No search can retain more rows than candidates, so clamp every
        # internal heap/capacity before allocation while preserving the caller's
        # validated positive value and exact untruncated match count.
        var effective_limit = min(limit, len(self._candidates))
        var query_keys = prepare_query_keys(self._language, query, case_mode)
        var incremental = self._can_refine(query, case_mode) and not (
            self._previous_was_identity
        )
        if (
            not incremental
            and self._language == LanguageMode.AUTO
            and len(self._candidates) >= 4_096
        ):
            return self._parallel_auto_search(
                query, case_mode, effective_limit, query_keys
            )
        var workspace = MatchWorkspace()
        var top_k = TopK(effective_limit)
        self._next_matching_indices.clear()
        self._last_scanned_count = 0
        self._last_scored_pair_count = 0
        self._last_position_reconstruction_count = 0

        if incremental:
            for previous_index in range(len(self._matching_indices)):
                self._scan_candidate(
                    self._matching_indices[previous_index],
                    query_keys,
                    workspace,
                    top_k,
                )
        else:
            for candidate_index in range(len(self._candidates)):
                self._scan_candidate(candidate_index, query_keys, workspace, top_k)

        var total_matches = len(self._next_matching_indices)
        var ranked = top_k^.take_ranked()
        var rows = List[RankedCandidate](capacity=len(ranked))
        var key_positions = List[Int]()
        for index in range(len(ranked)):
            var candidate_index = ranked[index].index
            var best = self._best_key_match(
                candidate_index, query_keys, workspace, False
            )
            debug_assert(best.matched)
            var reconstructed = workspace.match_into_at(
                query_keys[best.query_index].pattern,
                self._corpus,
                best.key_index,
                key_positions,
            )
            debug_assert(reconstructed.matched)
            self._last_position_reconstruction_count += 1
            ref candidate = self._candidates[candidate_index]
            var representation = candidate_representation_at(
                self._language,
                candidate.text,
                self._keys[best.key_index].bundle_ordinal,
            )
            var positions = project_key_positions(
                representation,
                key_positions,
                candidate.text,
            )
            rows.append(
                RankedCandidate(
                    candidate.source_index,
                    String(candidate.text),
                    best.score,
                    positions^,
                    self._keys[best.key_index].kind,
                )
            )

        var page = SearchPage(rows^, total_matches)
        self._replace_matches()
        self._last_incremental = incremental
        self._remember_query(query, case_mode)
        return page^


struct _SearchEntry(Copyable, ImplicitlyCopyable):
    var candidate_index: Int
    var best: _BestKeyMatch

    def __init__(out self, candidate_index: Int, best: _BestKeyMatch):
        self.candidate_index = candidate_index
        self.best = best


def _entry_worse(left: _SearchEntry, right: _SearchEntry) -> Bool:
    return left.best.score < right.best.score or (
        left.best.score == right.best.score
        and left.candidate_index > right.candidate_index
    )


struct _SearchPhase(Copyable, Equatable, ImplicitlyCopyable):
    var _value: Int

    comptime SCAN = _SearchPhase(_value=0)
    comptime DRAIN = _SearchPhase(_value=1)
    comptime REVERSE = _SearchPhase(_value=2)
    comptime DONE = _SearchPhase(_value=3)
    comptime IDENTITY = _SearchPhase(_value=4)

    def __init__(out self, *, _value: Int):
        self._value = _value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


struct CooperativeSearch:
    """One cancellable exact search, including bounded heap drain and reversal.

    No approximate scores or partial totals are published. The scan, position
    reconstruction, and ordering phases each advance by at most ``work_items``
    per call. One candidate's exact matcher is the indivisible work unit;
    the elapsed-time budget is checked between units, never inside Hibana.
    The ranking heap is O(min(limit, corpus size)); exact refinement retains
    O(match count) identities alongside the prepared query/workspace. Empty
    queries copy bounded source-order identity rows without weighted key scoring.
    """

    var generation: Int
    var query: String
    var case_mode: CaseMode
    var incremental: Bool
    var scan_count: Int
    var matching_indices: List[Int]
    var query_keys: List[PreparedQueryKey]
    var workspace: MatchWorkspace
    var limit: Int
    var scanned: Int
    var scored_pairs: Int
    var total_matches: Int
    var phase: _SearchPhase
    var reverse_index: Int
    var previous_id: Optional[Int]
    var selected_row: Optional[Int]
    var heap: List[_SearchEntry]
    var rows: List[RankedCandidate]
    var positions: List[Int]

    def __init__(
        out self,
        index: SearchIndex,
        query: StringSlice,
        case_mode: CaseMode,
        limit: Int,
        generation: Int,
        previous_id: Optional[Int] = None,
    ) raises:
        if limit < 1:
            raise Error("cooperative search limit must be >= 1; got ", limit)
        self.generation = generation
        self.query = String(query)
        self.case_mode = case_mode
        self.incremental = index._can_refine(query, case_mode) and (
            query == "" or not index._previous_was_identity
        )
        self.scan_count = 0 if query == "" else (
            len(index._matching_indices) if self.incremental else len(index)
        )
        self.matching_indices = List[Int]()
        self.query_keys = List[
            PreparedQueryKey
        ]() if query == "" else prepare_query_keys(index.language(), query, case_mode)
        self.workspace = MatchWorkspace()
        self.limit = min(limit, len(index))
        self.scanned = 0
        self.scored_pairs = 0
        self.total_matches = len(index) if query == "" else 0
        self.phase = _SearchPhase.IDENTITY if query == "" else _SearchPhase.SCAN
        self.reverse_index = 0
        self.previous_id = previous_id.copy()
        self.selected_row = None
        self.heap = List[_SearchEntry]()
        self.rows = List[RankedCandidate]()
        self.positions = List[Int]()

    def done(self) -> Bool:
        return self.phase == _SearchPhase.DONE

    def _sift_down(mut self):
        var current = 0
        while current * 2 + 1 < len(self.heap):
            var child = current * 2 + 1
            if child + 1 < len(self.heap) and _entry_worse(
                self.heap[child + 1], self.heap[child]
            ):
                child += 1
            if not _entry_worse(self.heap[child], self.heap[current]):
                break
            self.heap.swap_elements(child, current)
            current = child

    def _push(mut self, entry: _SearchEntry):
        if len(self.heap) < self.limit:
            self.heap.append(entry)
            var current = len(self.heap) - 1
            while current > 0:
                var parent = (current - 1) // 2
                if not _entry_worse(self.heap[current], self.heap[parent]):
                    break
                self.heap.swap_elements(current, parent)
                current = parent
        elif self.limit > 0 and _entry_worse(self.heap[0], entry):
            self.heap[0] = entry
            self._sift_down()

    def advance(
        mut self,
        mut index: SearchIndex,
        work_items: Int = 64,
        time_budget_ns: Int = 2_000_000,
    ) raises:
        """Do bounded work, returning to the terminal even during final sorting."""
        if work_items < 1 or time_budget_ns < 1:
            raise Error("search batch work_items and time_budget_ns must be >= 1")
        var started = perf_counter_ns()
        for _ in range(work_items):
            if self.phase == _SearchPhase.SCAN:
                if self.scanned == self.scan_count:
                    self.phase = _SearchPhase.DRAIN
                    continue
                var candidate_index = index._matching_indices[
                    self.scanned
                ] if self.incremental else self.scanned
                var best = index._best_key_match(
                    candidate_index, self.query_keys, self.workspace, False
                )
                self.scored_pairs += best.scored_pairs
                if best.matched:
                    self.total_matches += 1
                    self.matching_indices.append(candidate_index)
                    self._push(_SearchEntry(candidate_index, best))
                self.scanned += 1
            elif self.phase == _SearchPhase.DRAIN:
                if len(self.heap) == 0:
                    self.phase = _SearchPhase.REVERSE
                    continue
                self.heap.swap_elements(0, len(self.heap) - 1)
                var entry = self.heap.pop()
                self._sift_down()
                var best = entry.best
                var reconstructed = self.workspace.match_into_at(
                    self.query_keys[best.query_index].pattern,
                    index._corpus,
                    best.key_index,
                    self.positions,
                )
                debug_assert(reconstructed.matched)
                ref candidate = index._candidates[entry.candidate_index]
                var representation = candidate_representation_at(
                    index._language,
                    candidate.text,
                    index._keys[best.key_index].bundle_ordinal,
                )
                var positions = project_key_positions(
                    representation, self.positions, candidate.text
                )
                if (
                    self.previous_id
                    and candidate.source_index == self.previous_id.value()
                ):
                    self.selected_row = len(self.rows)
                self.rows.append(
                    RankedCandidate(
                        candidate.source_index,
                        String(candidate.text),
                        best.score,
                        positions^,
                        index._keys[best.key_index].kind,
                    )
                )
            elif self.phase == _SearchPhase.REVERSE:
                if self.reverse_index >= len(self.rows) // 2:
                    if self.selected_row:
                        self.selected_row = (
                            len(self.rows) - self.selected_row.value() - 1
                        )
                    swap(index._matching_indices, self.matching_indices)
                    index._last_scanned_count = self.scanned
                    index._last_scored_pair_count = self.scored_pairs
                    index._last_incremental = self.incremental
                    index._last_position_reconstruction_count = len(self.rows)
                    index._remember_query(self.query, self.case_mode)
                    self.phase = _SearchPhase.DONE
                    return
                self.rows.swap_elements(
                    self.reverse_index, len(self.rows) - self.reverse_index - 1
                )
                self.reverse_index += 1
            elif self.phase == _SearchPhase.IDENTITY:
                if len(self.rows) == self.limit:
                    # Identity is the corpus itself, as in SearchIndex.search:
                    # no weighted scoring or redundant [0..N) cache is needed.
                    index._matching_indices.clear()
                    index._next_matching_indices.clear()
                    index._last_scanned_count = 0
                    index._last_scored_pair_count = 0
                    index._last_position_reconstruction_count = 0
                    index._last_incremental = self.incremental
                    index._remember_query(self.query, self.case_mode)
                    self.phase = _SearchPhase.DONE
                    return
                ref candidate = index._candidates[len(self.rows)]
                if (
                    self.previous_id
                    and candidate.source_index == self.previous_id.value()
                ):
                    self.selected_row = len(self.rows)
                self.rows.append(
                    RankedCandidate(
                        candidate.source_index, String(candidate.text), 0, List[Int]()
                    )
                )
            else:
                return
            if perf_counter_ns() - started >= time_budget_ns:
                return

    def take_rows(var self) -> List[RankedCandidate]:
        debug_assert(self.done())
        var rows = List[RankedCandidate]()
        swap(rows, self.rows)
        return rows^
