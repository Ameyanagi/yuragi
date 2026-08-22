# Design

## Principles

- Mojo is the runtime implementation language.
- Prefer pure Mojo and safe standard-library APIs.
- Keep the root API small, typed, documented, and testable.
- Separate semantic contracts from optimized CPU, SIMD, GPU, terminal, or
  rendering backends.
- Establish correctness and reference fixtures before optimization.
- Make invalid public configuration unrepresentable when practical; otherwise
  reject it explicitly.
- Preserve source mappings, numerical tolerances, ownership, and provenance as
  first-class data when the domain requires them.
- Do not add a framework-wide array, executor, renderer, or application model.

## Tradeoffs

The project accepts a narrower initial feature set in exchange for reviewable
contracts and sparse dependencies. Generated tables are acceptable when their
sources, Unicode or data version, licenses, checksums, and deterministic update
procedure are committed. Consumers must not need the generator toolchain.

The direct-text slice verifies process, framing, I/O, deterministic Hibana
ranking, exact result cardinality, and interactive identity semantics. Phonetic
matching is added only through Yomi/Moji representations; Yuragi does not embed
temporary language tables or collapse generated matches to one bounding span.

The CLI reads the complete stream before selection in the foundation release.
This is the simplest deterministic ownership model. A bounded-memory streaming
or top-K design may replace it only after Hibana's matcher lifetime and ranking
contracts are known.

Language auto-detection is application policy owned by Yuragi. Yomi supplies
explicit Chinese, Japanese, and Korean representations; it does not decide how
mixed-script candidates are classified, ordered, or combined. That keeps
`--lang auto` predictable at the CLI layer and leaves reusable language
algorithms free of application defaults.

Generated shell integration is output-only and byte-stable. It does not edit a
profile or execute a finder while being generated. Runtime functions expose the
small fixed workflow set and check external dependencies immediately before
use, so installing a faster path finder does not require regenerating a script.
The `YURAGI_BIN` environment variable is the only executable override.

## Out of scope

Reusable fuzzy algorithms, Unicode primitives, phonetic tables, and terminal widgets belong in their owning libraries rather than this application.
