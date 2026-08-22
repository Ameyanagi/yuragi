# Yuragi implementation plan

This file records the application boundary, release gates, and evidence needed
for changes after `0.1.0`. Product outcomes live in `docs/roadmap.md`.

## Product boundary

Yuragi owns CLI policy, candidate ingestion, ranking orchestration, output,
shell integration, configuration, and the interactive application. It does not
own Unicode indexing, fuzzy scoring, phonetic data, source mappings, terminal
widgets, or low-level SIMD kernels.

The primary noninteractive contract is a newline-delimited UTF-8 filter:

```sh
printf '北京大学\nnotes\n' | yuragi --lang zh --filter bjdx
```

`--read0` and `--print0` switch either side independently to NUL framing. A
successful invocation writes only candidates to stdout; diagnostics go to
stderr. Equal-score results preserve source order.

## v0.1 release — implemented

- Parse the documented filter, interactive, language, case, framing,
  informational, shell, doctor, and configuration-path options without ignored
  or ambiguous flags.
- Read standard input in bounded chunks, preserve candidate text and source
  order, and render deterministic newline- or NUL-framed output.
- Own one internal prepared `SearchIndex` for filter and interactive workflows.
  Internal orchestration follows one pattern: construct the index, then call
  `index.search(query, case_mode, limit)`. Direct and explicit-language keys are
  prepared once per candidate. The executable package does not install or
  support this implementation as a Mojo library API.
- Scan through Hibana's score-only path, retain bounded top-K candidate/key
  identities, and reconstruct source positions only for final rows.
- Generate bounded, typed Yomi keys in explicit `ja`, `zh`, and `ko` modes.
  Compose Yomi source mappings with Moji coordinates so `--explain` and the TUI
  highlight the original candidate, including discontiguous ranges.
- Define `--lang auto` as direct-only. Yuragi does not guess a language from a
  mixed-script string and does not silently expand every phonetic system.
- Support Japanese kana/romaji, Chinese pinyin, and Korean romanized, initial,
  and keyboard representations exposed by Yomi `0.1.1`.
- Keep general Japanese Kanji readings behind a separately licensed dictionary
  provider. `日本語`/`nihongo` is intentionally not claimed in the built-in
  release.
- Use one inline MojoTUI picker over the same index, with lazy empty-query rows,
  stable cursor identity, query seeding, automation, and source-ordered
  multi-selection.
- Pin stable Mojo `1.0.0`, Hibana `0.1.0`, Moji `0.1.0`, MojoTUI `0.1.1`, and
  Yomi `0.1.1` exactly. Release builds consume installed packages, never sibling
  source trees.

Acceptance evidence is the locked unit suite, executable CLI and PTY contracts,
README compilation, installed-package direct/JA/ZH/KO/version smokes, and clean
source/package CI on macOS ARM64, Linux x86-64, and Linux ARM64.

## Performance policy

Performance work starts with profiles and reproducible workloads. The release
protocol uses three warmups and 31 measured samples, reports nearest-rank p50
and p95, validates checksums/counts, and separates preparation from search.
Record CPU, OS, compiler, commit, corpus, query, and result limit with every
published number.

Optimize ownership, prepared storage, allocation-free scoring, final-only
position reconstruction, and coarse candidate parallelism before considering
SIMD. The fuzzy kernel has loop-carried pattern state and divergent Unicode
early exits; add SIMD only when a profile identifies a fixed-width independent
kernel and the same benchmark shows a repeatable win without semantic drift.
See `benchmarks/README.md`, `benchmarks/fair-search-protocol.md`, and
`benchmarks/cjk-search-protocol.md`.

## Release workflow

1. Update versions and exact pins, regenerate `pixi.lock` with Pixi, and run the
   complete locked check/package suite. Never edit the lockfile manually.
2. Merge only after three-platform source and installed-package CI passes.
3. Create one annotated version tag at the exact tested `main` commit.
4. Verify the canonical source archive's SHA-256 before every extraction and
   gate the GitHub source release on all source/package jobs.
5. Publish the immutable tag through `Ameyanagi/mojo-channel`, then smoke-test a
   clean public install on all three platform subdirectories.

## Later gates

- A licensed Japanese dictionary provider with explicit provenance, versioning,
  deterministic generation, and opt-in configuration.
- Preview and cancellation using the same search core and terminal host.
- Configuration loading only after a complete, tested parser exists; path
  resolution does not imply partial TOML support.
- Coarse parallel exact ranking when profiles justify its startup and merge
  overhead on representative corpora.

## Explicitly not in Yuragi

- Unicode databases, segmentation, width, and index mapping
- fuzzy score algorithms or generic SIMD kernels
- pinyin, kana, Hangul, or keyboard conversion tables
- terminal rendering, layout, and widgets
- an installed or supported Mojo library package for Yuragi's internal
  orchestration
- heuristic `auto` language detection presented as complete CJK support
