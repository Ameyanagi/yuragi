# Design

## Principles

- Mojo is the runtime implementation language.
- Prefer pure Mojo and safe standard-library APIs.
- Keep internal module boundaries small, typed, documented, and testable.
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

The application verifies process, framing, I/O, deterministic Hibana ranking,
exact result cardinality, and interactive identity semantics. Phonetic matching
is provided only through Yomi/Moji representations; Yuragi does not embed
temporary language tables or collapse generated matches to one bounding span.

Input is framed incrementally as raw chunks arrive. Only the current record
keeps undecoded bytes; completed records transfer directly into candidate-owned
strings. The picker opens after EOF, preserving the deterministic corpus model.
`--max-input-bytes`, `--max-candidates`, and `--max-record-bytes` impose explicit
positive budgets, independently of the result `--limit`. Exceeding a budget
fails before retaining the excess byte/record and exits 2 with its flag, value,
and correction. Defaults are 256 MiB, 1,000,000 records, and 1 MiB per record.
Raw record bytes exclude the delimiter and include a CR before LF; that CR is
removed only after framing. Invalid UTF-8 retains one replacement per invalid
byte. Ctrl-C interrupts a waiting input read through normal terminal SIGINT.
The retained strings and prepared index add overhead to the raw-byte budget;
these settings bound input rather than claiming an exact RSS ceiling.

Interactive searches use an owned, generation-tagged `CooperativeSearch`.
Scoring, heap draining, exact position reconstruction, and final reversal all
advance by at most 64 work items or a 2 ms elapsed-time budget per terminal turn.
One candidate's exact Hibana match is indivisible; this is a cooperative bound,
not a hard wall-clock deadline for pathological records or enormous queries.
Public runtime-adapter deadlines are armed only while a search is active, so
an idle picker does not wake on a periodic search timer. Scheduled turns carry
the generation that created them, so obsolete turns cannot publish results. The UI hides old rows and displays `matches=?` and `Searching` until
an exact current-generation result is complete; Enter cannot accept stale rows.
Selection is restored by stable source identity, and marks survive query edits.
Large seeded queries follow the same path unless exact pre-picker automation
(`--select-1`/`--exit-0`) was requested. Filter ranking remains synchronous and
uses the unchanged exact search entry point.

Marks use hash membership with monotonic insertion ordinals, making membership
and toggling expected O(1). Accepting marks makes one corpus-order pass with
O(N + M) work and O(M) output ownership. Text duplicates remain distinct by
source identity; unmarking and remarking gets a new insertion ordinal, while
emitted candidates retain source order. The result limit also caps mark count.
See `benchmarks/interactive-responsiveness.md` for reproducible measurements.

Yuragi defines `--lang auto` as direct-only rather than attempting language
detection. Yomi supplies explicit Chinese, Japanese, and Korean
representations; it does not decide how mixed-script candidates are classified,
ordered, or combined. This keeps the default predictable and leaves reusable
language algorithms free of application heuristics.

Generated shell integration is output-only and byte-stable. It does not edit a
profile or execute a finder while being generated. Runtime functions expose the
small fixed workflow set and check external dependencies immediately before
use, so installing a faster path finder does not require regenerating a script.
The `YURAGI_BIN` environment variable is the only executable override.

## Out of scope

Reusable fuzzy algorithms, Unicode primitives, phonetic tables, and terminal widgets belong in their owning libraries rather than this application.
