# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses semantic versioning after the first public release.

## [Unreleased]

### Fixed

- Update Yomi and MojoTUI to `0.1.2`, including the fix for native Japanese
  queries such as `--lang ja --filter カ` aborting on a UTF-8 boundary assertion.
  Workspace and installed-package tests verify the original candidate output.

## [0.1.0] - 2026-08-22

This is Yuragi's first source-tagged and three-platform packaged release.

### Added

- One prepared `SearchIndex` shared by filter and interactive workflows, with
  bounded top-K output and final-only match-position reconstruction.
- Explicit Japanese, Chinese, and Korean phonetic search backed by Yomi's
  typed, source-mapped keys, while `--lang auto` remains predictable
  direct-text matching.
- Original-text highlights for generated-key matches, including discontiguous
  source ranges.
- Exact stable Mojo 1.0.0 and ecosystem dependency pins plus installed-package
  direct, language, and version smoke tests.
- SHA-pinned three-platform source/package CI and a gated, checksummed source
  release workflow.
- Validated `--filter`, `--lang`, `--help`, and `--version` option parsing.
- Safe, chunked UTF-8 candidate ingestion from standard input.
- Deterministic newline-delimited output and empty-query identity selection.
- Explicit Moji, Hibana, and Yomi dependency gates for non-empty matching.
- Unit and executable CLI contract tests for the first application slice.
- Defined CRLF framing and help/version/invalid-option precedence at the
  executable boundary.
- Distinguished no-match exit status 1 from usage, unsupported-mode,
  operational, and input failures at exit status 2, and made executable
  framing/package tests byte-exact.
- Made `--lang auto` an application-owned policy and tightened Moji/Yomi
  dependency gates around search coordinates and discontiguous source ranges.
- Added deterministic controlled-chunk and byte-exact executable fixtures for
  a multibyte CJK scalar straddling the nominal 4 KiB buffer layout, without
  assuming that operating-system reads fill the requested span.
