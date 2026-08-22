"""Bounded Yomi key preparation and exact highlight projection."""

from hibana import CaseMode
from hibana.pattern import Pattern
from hibana.prepared import PreparedCorpus
from moji import ByteOffset, CodePointIndex, TextIndex
from std.collections import List
from yomi import (
    PhoneticRepresentation,
    SearchKeyBundle,
    SearchKeyKind,
    SourceMapping,
    chinese_candidate_keys,
    chinese_query_keys,
    japanese_candidate_keys,
    japanese_query_keys,
    korean_candidate_keys,
)

from yuragi.language import LanguageMode


struct IndexedPhoneticKey(Copyable):
    """One flattened candidate key parallel to a PreparedCorpus slot."""

    var candidate_index: Int
    var kind: SearchKeyKind
    var weight: Int
    var bundle_ordinal: Int

    def __init__(
        out self,
        candidate_index: Int,
        kind: SearchKeyKind,
        weight: Int,
        bundle_ordinal: Int,
    ):
        self.candidate_index = candidate_index
        self.kind = kind
        self.weight = weight
        self.bundle_ordinal = bundle_ordinal


struct PreparedQueryKey(Copyable):
    """One typed query pattern prepared once per broad corpus scan."""

    var kind: SearchKeyKind
    var weight: Int
    var pattern: Pattern

    def __init__(
        out self,
        kind: SearchKeyKind,
        weight: Int,
        var pattern: Pattern,
    ):
        self.kind = kind
        self.weight = weight
        self.pattern = pattern^


def _identity_representation(source: StringSlice) -> PhoneticRepresentation:
    var owned = String(source)
    var mappings = List[SourceMapping](capacity=source.byte_length())
    var cursor = 0
    for scalar in StringSlice(owned).codepoint_slices():
        var end = cursor + scalar.byte_length()
        mappings.append(SourceMapping._from_validated(cursor, end, cursor, end))
        cursor = end
    return PhoneticRepresentation._from_validated(owned.copy(), owned^, mappings^)


def _append_representation(
    candidate_index: Int,
    kind: SearchKeyKind,
    weight: Int,
    bundle_ordinal: Int,
    var representation: PhoneticRepresentation,
    mut corpus: PreparedCorpus,
    mut keys: List[IndexedPhoneticKey],
):
    var text = representation.text()
    corpus.append(text)
    keys.append(IndexedPhoneticKey(candidate_index, kind, weight, bundle_ordinal))


def _append_bundle(
    candidate_index: Int,
    var bundle: SearchKeyBundle,
    mut corpus: PreparedCorpus,
    mut keys: List[IndexedPhoneticKey],
):
    var source_keys = bundle^.take_keys()
    var bundle_ordinal = 0
    while len(source_keys) > 0:
        var key = source_keys.pop(0)
        var kind = key.kind()
        var weight = key.weight()
        var representation = key^.take_representation()
        _append_representation(
            candidate_index,
            kind,
            weight,
            bundle_ordinal,
            representation^,
            corpus,
            keys,
        )
        bundle_ordinal += 1


def append_candidate_keys(
    language: LanguageMode,
    candidate_index: Int,
    text: StringSlice,
    mut corpus: PreparedCorpus,
    mut keys: List[IndexedPhoneticKey],
) raises:
    """Append one candidate's bounded key family in deterministic order."""
    language.validate()
    if language == LanguageMode.AUTO:
        var representation = _identity_representation(text)
        _append_representation(
            candidate_index,
            SearchKeyKind.ORIGINAL,
            0,
            0,
            representation^,
            corpus,
            keys,
        )
    elif language == LanguageMode.JA:
        var bundle = japanese_candidate_keys(text)
        _append_bundle(candidate_index, bundle^, corpus, keys)
    elif language == LanguageMode.ZH:
        var bundle = chinese_candidate_keys(text)
        _append_bundle(candidate_index, bundle^, corpus, keys)
    else:
        var bundle = korean_candidate_keys(text)
        _append_bundle(candidate_index, bundle^, corpus, keys)


def _append_query_bundle(
    var bundle: SearchKeyBundle,
    source: StringSlice,
    case_mode: CaseMode,
    mut output: List[PreparedQueryKey],
):
    var exact_case = case_mode == CaseMode.EXACT
    if case_mode == CaseMode.SMART_ASCII:
        for scalar in source.codepoints():
            var value = scalar.to_u32()
            if value >= UInt32(65) and value <= UInt32(90):
                exact_case = True
                break
    var keys = bundle^.take_keys()
    while len(keys) > 0:
        var key = keys.pop(0)
        var kind = key.kind()
        var weight = key.weight()
        var text = key.text()
        # A normalization that changes an exact-case query must not silently
        # bypass Hibana's public exact/smart-case policy. Same-text typed keys
        # remain useful for compatibility gates such as Chinese initials.
        if exact_case and text != source:
            continue
        output.append(PreparedQueryKey(kind, weight, Pattern(text, case_mode)))


def prepare_query_keys(
    language: LanguageMode,
    query: StringSlice,
    case_mode: CaseMode,
) raises -> List[PreparedQueryKey]:
    """Prepare the bounded query variants for an explicit language policy."""
    language.validate()
    var output = List[PreparedQueryKey]()
    if language == LanguageMode.JA:
        var bundle = japanese_query_keys(query)
        _append_query_bundle(bundle^, query, case_mode, output)
    elif language == LanguageMode.ZH:
        var bundle = chinese_query_keys(query)
        _append_query_bundle(bundle^, query, case_mode, output)
    else:
        # Korean's original query kind intentionally gates romanized,
        # choseong, and keyboard candidate keys. AUTO has only an original
        # candidate key, and zero weights preserve Yuragi's direct-search
        # score contract.
        var weight = (
            0 if language
            == LanguageMode.AUTO else SearchKeyKind.QUERY_ORIGINAL.default_weight()
        )
        output.append(
            PreparedQueryKey(
                SearchKeyKind.QUERY_ORIGINAL,
                weight,
                Pattern(query, case_mode),
            )
        )
    return output^


def candidate_representation_at(
    language: LanguageMode,
    source: StringSlice,
    bundle_ordinal: Int,
) raises -> PhoneticRepresentation:
    """Regenerate one finalist key without retaining per-key source copies."""
    language.validate()
    if language == LanguageMode.AUTO:
        if bundle_ordinal != 0:
            raise Error("direct candidate key ordinal must be zero")
        return _identity_representation(source)

    if language == LanguageMode.JA:
        var bundle = japanese_candidate_keys(source)
        var key = bundle.key(bundle_ordinal)
        return key^.take_representation()
    if language == LanguageMode.ZH:
        var bundle = chinese_candidate_keys(source)
        var key = bundle.key(bundle_ordinal)
        return key^.take_representation()
    var bundle = korean_candidate_keys(source)
    var key = bundle.key(bundle_ordinal)
    return key^.take_representation()


def key_kind_name(kind: SearchKeyKind) -> String:
    """Return the stable lowercase label used by reports and profiles."""
    if kind == SearchKeyKind.ORIGINAL:
        return String("original")
    if kind == SearchKeyKind.NORMALIZED:
        return String("normalized")
    if kind == SearchKeyKind.JAPANESE_KANA:
        return String("ja-kana")
    if kind == SearchKeyKind.JAPANESE_ROMAJI:
        return String("ja-romaji")
    if kind == SearchKeyKind.CHINESE_PINYIN_FULL:
        return String("zh-pinyin-full")
    if kind == SearchKeyKind.CHINESE_PINYIN_JOINED:
        return String("zh-pinyin-joined")
    if kind == SearchKeyKind.CHINESE_PINYIN_INITIALS:
        return String("zh-pinyin-initials")
    if kind == SearchKeyKind.KOREAN_ROMANIZED:
        return String("ko-romanized")
    if kind == SearchKeyKind.KOREAN_INITIALS:
        return String("ko-initials")
    if kind == SearchKeyKind.KOREAN_KEYBOARD:
        return String("ko-keyboard")
    if kind == SearchKeyKind.LEARNED_ALIAS:
        return String("learned-alias")
    return String("unknown")


def _insert_position(mut positions: List[Int], value: Int):
    """Insert a source scalar index while preserving strict ordering."""
    var destination = 0
    while destination < len(positions) and positions[destination] < value:
        destination += 1
    if destination < len(positions) and positions[destination] == value:
        return
    positions.insert(destination, value)


def project_key_positions(
    representation: PhoneticRepresentation,
    key_positions: Span[Int, _],
    source_text: StringSlice,
) raises -> List[Int]:
    """Project key-scalar matches to exact original-source scalar indices."""
    var key_text = representation.text()
    var key_index = TextIndex(key_text)
    var source_index = TextIndex(source_text)
    var output = List[Int]()
    for position_index in range(len(key_positions)):
        var position = key_positions[position_index]
        var key_range = key_index.byte_range(
            CodePointIndex(position), CodePointIndex(position + 1)
        )
        var source_ranges = representation.source_ranges_for_output(
            key_range.start(), key_range.end()
        )
        for range_index in range(len(source_ranges)):
            var source_start = source_index.code_point_index(
                ByteOffset(source_ranges[range_index].start())
            ).value()
            var source_end = source_index.code_point_index(
                ByteOffset(source_ranges[range_index].end())
            ).value()
            for source_position in range(source_start, source_end):
                _insert_position(output, source_position)
    return output^
