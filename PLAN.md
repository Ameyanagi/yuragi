# Yuragi implementation plan

This is the execution plan for the application. `docs/roadmap.md` describes
release outcomes; this file records dependency gates, work order, and evidence
required to cross each gate.

## Product boundary

Yuragi owns CLI policy, candidate ingestion, ranking policy, output, shell
integration, configuration, and the interactive application. It does not
own Unicode segmentation, transformed-to-source mappings, fuzzy scoring, CJK
phonetic conversion, or terminal widgets.

The first product contract is a Unix filter:

```sh
printf "北京大学\nnotes\n" | yuragi --lang zh --filter bjdx
```

Input and output are newline-delimited UTF-8; `--read0` and `--print0` switch
either side independently to NUL framing while the complete stream is still
validated as UTF-8. A successful invocation writes only candidates to stdout.
Diagnostics go to stderr. Equal-score results preserve source order. CR is
removed only as the CRLF delimiter prefix; a CR in an unterminated final record
remains candidate data.

## Current foundation — implemented

- Parse `--filter`, `--query`, `--select-1`, `--exit-0`, `--multi`, `--limit`,
  `--lang`, `--read0`, `--print0`, `--help`, and `--version` without accepting
  ambiguous positionals or duplicate selections.
- Use Hibana smart ASCII case matching by default. `-i`/`--ignore-case` and
  `--no-ignore-case` are hard overrides that map directly to Hibana
  `CaseMode.IGNORE_ASCII` and `CaseMode.EXACT`.
- Read piped stdin through the public `FileDescriptor.read_bytes()` API and
  validate UTF-8 at the effect boundary after byte aggregation. A controlled
  unit test forces one UTF-8 scalar across a chunk boundary; the compiled CLI
  fixture covers the nominal 4 KiB buffer layout without assuming full reads.
- Preserve Unicode candidate text, blank candidates, and source order.
- Render newline- or NUL-delimited candidates deterministically.
- Execute empty-query filtering as identity selection, with optional
  input-order truncation through `--limit`.
- Rank non-empty direct matches through the installed Hibana package with a
  bounded top-K path. The documented ordering is score descending, then input
  order.
- Own interactive candidates in one `SearchIndex`. Identical queries and safe
  direct-text extensions scan only the previous complete exact match-ID set;
  backspace, arbitrary edits, and case changes fall back to a full scan.
- Keep the empty-query identity state lazy: retain exact cardinality and source
  order without building one ranked row per candidate, materialize only the
  visible viewport, and do not retain a redundant full-corpus identity-index
  list.
- Run the default no-`--filter` mode as a fixed-height inline MojoTUI picker
  behind `src/yuragi/interactive.mojo`. It reuses the Hibana ranking pipeline,
  keeps cursor identity by candidate source index across query refinements, and
  writes terminal UI through `/dev/tty` rather than stdout.
- Apply the interactive flag matrix before constructing the picker: `--query`
  seeds the prompt and initial ranking, `--select-1` accepts a sole initial
  match, and `--exit-0` exits 1 on an empty initial match set. The automation
  flags compose and evaluate the seeded query; `--multi` enables TAB/Shift-TAB
  marking. All four flags are usage errors with `--filter`.
- Store interactive marks as candidate source indices in mark order, independent
  of the ranked view. Marks survive query refinement, render visibly with a
  marked count, and resolve to newline- or NUL-framed output in source order;
  Enter falls back to the cursor candidate when no marks exist.
- Exercise the compiled picker through a real PTY (resolved from the first
  standard descriptor that is a terminal, macOS-safe) while candidate input
  and accepted output remain separate pipes. The contract test covers narrowing,
  acceptance, both abort keys, pre-TUI automation, multi-selection, source-order
  output, and terminal-attribute restoration without timing sleeps.
- Exit with code 1 and empty stdout when a non-empty query has no match.
  Invalid usage, unsupported modes, and input, operational, and internal
  failures exit 2. Exit 130 is active for interactive abort (the fzf/skim
  convention). Explicit phonetic language matching remains gated on Yomi; no
  temporary substring or language logic is hidden in Yuragi.

Evidence: unit tests, the `test-cli` and `test-interactive` executable contract
tests, `pixi run check`, and `pixi run build`.

## Integration gate A — Moji text contract

Entry criteria:

- Moji exposes an owned or safely borrowed search text view.
- Search positions have one documented coordinate system shared with Hibana.
- Transformed search positions can map back to exact original source ranges.
- Empty strings, combining marks, emoji, malformed boundaries, and CJK fixtures
  are covered by Moji tests.
- Yuragi can pin an installable Moji version in Pixi and the Conda recipe.

Yuragi work after the gate: wrap each `Candidate` in the agreed text view and
add integration fixtures. Display columns and terminal width remain owned by
MojoTUI. Do not copy search boundary, mapping, or display-width code locally.

## Integration gate B — Hibana matching contract (crossed)

Gate B is crossed for direct matching. Hibana is pinned as an installable
Conda package from a local channel, and Yuragi consumes the installed `hibana`
module rather than sibling source paths. Non-empty `--filter` ranks with score
descending followed by input order, and no-match exit code 1 is active.

Entry criteria:

- Hibana exposes a deterministic matcher with matched state, score, and source
  positions.
- Empty-query behavior, case policy, score ordering, and path policy are
  documented.
- Hibana accepts the Moji representation without Yuragi-specific adapters in
  the scoring algorithm.
- Representative ASCII, Unicode, and stable-tie fixtures pass.
- Yuragi can pin an installable Hibana version.

Completed Yuragi work: the non-empty-query rejection is replaced by matcher
orchestration, stable tie-breaking, bounded top-K selection, and byte-exact
`--filter` CLI tests. Scoring remains entirely in Hibana.

## Integration gate C — Yomi representation contract (source crossed; package pending)

Yomi source now exposes typed, weighted candidate/query keys for Japanese,
Korean, and Chinese, exact generated-to-source mappings, bounded Japanese
candidate/query fanout, learned aliases, numeric readings, and explicit kind
compatibility. Japanese candidate generation retains original and normalized
base keys under an eight-key/1,024-byte default budget. Full NFKC and licensed
Kanji readings remain declared provider gates rather than partial claims.

The remaining entry criterion is publication of immutable `mojo-yomi` and the
new prepared `mojo-hibana` version on every supported platform. Yuragi does not
use sibling checkout imports while that publication is pending.

Entry criteria:

- Yomi exposes distinct language-specific representation APIs for Chinese,
  Japanese, and Korean rather than an application-level `auto` mode.
- A matched output range resolves to ordered exact source ranges, preserving
  discontiguous highlights without replacing them with one bounding span.
- Korean decomposition, kana romanization, and the first pinyin table release
  declare data provenance and licenses.
- Yomi representations compose with the Moji/Hibana contracts without losing
  original-character highlighting positions.
- Yuragi can pin an installable Yomi version.

Yuragi work after package publication: generate direct and phonetic candidate views, merge
their Hibana results under a documented ranking policy, and prove that matches
highlight the original CJK source ranges.

The ranking policy for merged direct+phonetic results is specified in
`docs/multi-key-design.md`.

Yuragi owns `--lang auto`: its application policy will define script detection,
mixed-script ordering, explicit-language precedence, and fallback behavior. Yomi
provides language-specific representations and does not choose for the user.

## v0.1 completion workflow

1. Land gates A, B, and C independently; never use sibling-source imports in a
   release build.
2. Add pinned dependencies and installed-package smoke tests.
3. Make the motivating `bjdx` command succeed with exact stdout fixtures.
4. Cover empty input, blank candidates, invalid UTF-8, all language modes,
   stable ties, no matches, and large streamed inputs.
5. Record benchmark methodology for ingestion, representation, matching, and
   top-K separately.
6. Run `pixi run --locked check` on every supported CI target and build the
   Conda package from a clean source archive.
7. Publish only after README and compatibility claims match observed behavior.

The channel workflow must build both libraries from immutable tag refs for
`osx-arm64`, `linux-64`, and `linux-aarch64`. Publish under new versions rather
than replacing the hosted Hibana `0.0.0` artifact, then pin both versions and
regenerate Yuragi's three-platform lock before enabling the integration.

## Later gates

- Preview, filesystem traversal, shell bindings, and configuration follow the
  same CLI/search core rather than creating alternate match pipelines.
- Performance work follows representative benchmarks and must not change
  ordering or mapping semantics.

## Explicitly not in Yuragi

- Unicode databases, segmentation, width, and index mapping
- fuzzy score algorithms or SIMD kernels
- pinyin, kana, Hangul, or keyboard conversion tables
- terminal rendering, layout, and widgets
- a reusable public library API for application-internal orchestration
