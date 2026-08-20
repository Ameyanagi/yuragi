# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses semantic versioning after the first public release.

## [Unreleased]

### Added

- Validated `--filter`, `--lang`, `--help`, and `--version` option parsing.
- Safe, chunked UTF-8 candidate ingestion from standard input.
- Deterministic newline-delimited output and empty-query identity selection.
- Explicit Moji, Hibana, and Yomi dependency gates for non-empty matching.
- Unit and executable CLI contract tests for the first application slice.
- Defined CRLF framing and help/version/invalid-option precedence at the
  executable boundary.
- Distinguished usage/unsupported-mode exit status 2 from operational/input
  exit status 1, and made executable framing/package tests byte-exact.
- Made `--lang auto` an application-owned policy and tightened Moji/Yomi
  dependency gates around search coordinates and discontiguous source ranges.
- Added deterministic controlled-chunk and byte-exact executable fixtures for
  a multibyte CJK scalar straddling the nominal 4 KiB buffer layout, without
  assuming that operating-system reads fill the requested span.
- Added a primary-source finder reference architecture covering the shared
  search core, filter/interactive controllers, dependency adapters, streaming
  constraints, ranking/language ownership, process contracts, and issue order.
