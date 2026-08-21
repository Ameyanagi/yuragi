# Roadmap

## v0.1 — Foundation

- Stabilize newline-delimited UTF-8 stdin/stdout and CLI error contracts.
- Integrate pinned Moji text views and transformed-to-source mappings.
- Integrate pinned Hibana deterministic scoring, positions, and stable ranking.
- Integrate pinned Yomi phonetic representations for `auto`, `zh`, `ja`, and
  `ko` without losing source ranges.
- Make `printf "北京大学\nnotes\n" | yuragi --lang zh --filter bjdx` emit the
  correct original candidate.
- Add unit, reference-value, invariant, installed-package, and executable CLI
  coverage on every supported target.
- Build and test the Conda application package from a clean source archive.

The options/ingestion/output foundation is implemented. Non-empty matching is
still dependency-gated; see `PLAN.md` for entry criteria and work order.

## v0.2 — Usability

- Add interactive selection through MojoTUI without creating a second search
  pipeline.
- Add preview, configuration, and cancellation around the v0.1 core.
- Expand integration fixtures and publish shell usage guidance.

## v0.3 — Performance

- Add reproducible end-to-end benchmarks and representative CJK datasets.
- Add bounded-memory ingestion or incremental top-K when measurements require
  it.
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
