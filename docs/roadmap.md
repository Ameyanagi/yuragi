# Roadmap

## v0.1 — Foundation

- [x] Stabilize newline-delimited UTF-8 stdin/stdout and CLI error contracts.
- Integrate pinned Moji text views and transformed-to-source mappings.
- [x] Integrate pinned Hibana deterministic scoring, positions, and stable ranking.
- Publish and integrate pinned Yomi phonetic representations for `auto`, `zh`, `ja`, and
  `ko` without losing source ranges.
- Make `printf "北京大学\nnotes\n" | yuragi --lang zh --filter bjdx` emit the
  correct original candidate.
- [x] Add unit, reference-value, invariant, and executable CLI/PTY
  coverage on every supported target.
- [x] Build and test the Conda application package from a clean source archive.

Direct-text filtering, the interactive picker, exact incremental match-set
reuse, and Yomi's source-side typed multi-key APIs are implemented. Product
phonetic indexing remains gated only on immutable Hibana/Yomi package releases;
see `PLAN.md` for the publication and integration order.

## v0.2 — Usability

- [x] Add interactive selection through MojoTUI without creating a second search
  pipeline.
- Add preview and cancellation around the v0.1 core.
- [x] Reserve deterministic configuration resolution and publish shell usage
  guidance with generated bindings and `doctor` diagnostics.

## v0.3 — Performance

- [x] Add a reproducible bounded-search orchestration benchmark.
- [x] Add a fair 31-sample Yuru/Yuragi full and incremental search protocol.
- Add representative licensed CJK datasets and language-indexing benchmarks.
- [x] Reuse the prior complete exact match set for safe query extensions.
- [x] Add lazy, viewport-bounded identity-row resolution without retaining a
  redundant full-corpus identity-index list.
- Optimize measured orchestration bottlenecks without moving Hibana, Yomi, or
  Moji responsibilities into the application.

## v1.0 — Stability

- Document every CLI, configuration, output, and error contract.
- Provide a compatibility and deprecation policy.
- Support the declared OS and architecture matrix in CI.
- Require proof from shell and editor integrations.

## Not planned

Reusable fuzzy algorithms, Unicode primitives, phonetic tables, terminal
widgets, a public library API, filesystem indexing, and a GUI toolkit belong in
their owning projects or later applications.
