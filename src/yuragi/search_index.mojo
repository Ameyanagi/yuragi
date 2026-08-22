"""Persistent, prepared CJK-aware search state."""

from hibana import CaseMode, MatchResult, Scheme, TopK
from hibana.fast import fast_score_at
from hibana.parallel import rank_corpus_exact
from hibana.prepared import MatchWorkspace, PreparedCorpus
from std.collections import List
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
        var key_start = self._candidate_key_offsets[candidate_index]
        var key_end = self._candidate_key_offsets[candidate_index + 1]
        for key_index in range(key_start, key_end):
            ref key = self._keys[key_index]
            for query_index in range(len(query_keys)):
                ref query_key = query_keys[query_index]
                if not search_key_kinds_compatible(query_key.kind, key.kind):
                    continue
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

        var query_keys = prepare_query_keys(self._language, query, case_mode)
        var incremental = self._can_refine(query, case_mode) and not (
            self._previous_was_identity
        )
        if (
            not incremental
            and self._language == LanguageMode.AUTO
            and len(self._candidates) >= 4_096
        ):
            return self._parallel_auto_search(query, case_mode, limit, query_keys)
        var workspace = MatchWorkspace()
        var top_k = TopK(limit)
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
