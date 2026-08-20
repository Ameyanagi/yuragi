# Yuragi implementation plan

This is the execution plan for the application. `docs/roadmap.md` describes
release outcomes; this file records dependency gates, work order, and evidence
required to cross each gate.

## Product boundary

Yuragi owns CLI policy, candidate ingestion, ranking policy, output, shell
integration, configuration, and—later—the interactive application. It does not
own Unicode segmentation, transformed-to-source mappings, fuzzy scoring, CJK
phonetic conversion, or terminal widgets.

The first product contract is a Unix filter:

```sh
printf "北京大学\nnotes\n" | yuragi --lang zh --filter bjdx
```

Input and output are newline-delimited UTF-8. A successful invocation writes
only candidates, one per line, to stdout. Diagnostics go to stderr. Equal-score
results preserve source order. CR is removed only as the CRLF delimiter prefix;
a CR in an unterminated final record remains candidate data.

## Current foundation — implemented

- Parse `--filter`, `--lang`, `--help`, and `--version` without accepting
  ambiguous positionals or duplicate filter/language selections.
- Read piped stdin through the public `FileDescriptor.read_bytes()` API and
  validate UTF-8 at the effect boundary after byte aggregation. A controlled
  unit test forces one UTF-8 scalar across a chunk boundary; the compiled CLI
  fixture covers the nominal 4 KiB buffer layout without assuming full reads.
- Preserve Unicode candidate text, blank candidates, and source order.
- Render newline-delimited candidates deterministically.
- Execute empty-query filtering as identity selection.
- Reject non-empty filtering with exit code 2 and an explicit dependency-gate
  diagnostic. Invalid usage and unsupported modes exit 2; input, operational,
  and internal failures exit 1. No temporary substring or language logic is
  hidden in Yuragi.

Evidence: unit tests, the `test-cli` executable contract test, `pixi run check`,
and `pixi run build`.

## Integration gate A — Moji text contract

Entry criteria:

- Moji exposes an owned or safely borrowed search text view.
- Search positions have one documented coordinate system shared with Hibana.
- Transformed search positions can map back to exact original source ranges.
- Empty strings, combining marks, emoji, malformed boundaries, and CJK fixtures
  are covered by Moji tests.
- Yuragi can pin an installable Moji version in Pixi and the Conda recipe.

Yuragi work after the gate: wrap each `Candidate` in the agreed text view and
add integration fixtures. Display columns and terminal width are not required
for noninteractive search; they enter with the later MojoTUI gate. Do not copy
search boundary or mapping code locally.

## Integration gate B — Hibana matching contract

Entry criteria:

- Hibana exposes a deterministic matcher with matched state, score, and source
  positions.
- Empty-query behavior, case policy, score ordering, and path policy are
  documented.
- Hibana accepts the Moji representation without Yuragi-specific adapters in
  the scoring algorithm.
- Representative ASCII, Unicode, and stable-tie fixtures pass.
- Yuragi can pin an installable Hibana version.

Yuragi work after the gate: replace the current non-empty-query rejection with
matcher orchestration, define stable tie-breaking, and add `--filter` CLI tests.
Scoring remains entirely in Hibana.

## Integration gate C — Yomi representation contract

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

Yuragi work after the gate: generate direct and phonetic candidate views, merge
their Hibana results under a documented ranking policy, and prove that matches
highlight the original CJK source ranges.

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

## Later gates

- Interactive mode begins only after the noninteractive core is stable and
  adds MojoTUI behind an application adapter.
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
