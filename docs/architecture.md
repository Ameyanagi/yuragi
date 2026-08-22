# Architecture

Yuragi owns command-line orchestration, candidate ingestion, ranking policy,
output, configuration, shell integration, and the interactive application.

## Dependency boundary

Allowed ecosystem dependencies: Hibana, Yomi, Moji, and MojoTUI.
Expected downstream consumers: Command-line users, shell integrations, editors, and scripts.

Dependencies point from applications and higher-level packages toward smaller
foundations. This repository must never import a downstream consumer. New
dependencies require a documented need and must not force unrelated users to
install an application, renderer, language layer, or scientific stack.

## Layers

```text
main / process exit policy
        |
        v
options ---- stdin/stdout effect boundary
        |              |
        v              v
candidate model ---- selection orchestration
                           |
                 +---------+---------+
                 |         |         |
               Moji     Hibana     Yomi

        MojoTUI owns interactive terminal mechanics only
```

The implemented foundation includes options, whole-stream UTF-8 ingestion,
candidate framing, output framing, prepared direct and explicit-language key
sets, exact pre-limit match counts, bounded top-K rows, and an inline MojoTUI
picker. An empty query is identity selection. The picker and filter share the
same `SearchIndex`; retained rows never stand in for the total match count, and
cursor identity follows the source candidate across query changes.

The empty interactive query is represented as a lazy identity view. Its exact
cardinality and cursor IDs come directly from the owned `SearchIndex`; only the
visible viewport is materialized into MojoTUI `ListItem` values. Before the
terminal host is constructed, `FinderSession` swaps its live movable model with
an empty placeholder and moves the live model into the host. The host then owns
that model for the run; the session extracts only the outcome and accepted
records afterward. No `FinderModel`, `SearchIndex`, prepared key corpus, or
candidate corpus is copied across this boundary.

Interactive candidate rendering is also a display-only boundary. C0 controls
and DEL are rendered as their Unicode control-picture symbols so a candidate
cannot invisibly move the cursor or inject terminal control behavior. The
stored candidate record is not rewritten: accepting it emits its original
valid UTF-8 record and requested framing unchanged. Invalid UTF-8 continues to
follow the documented lossy-decoding contract.

## Search state and ranking contracts

The executable's internal orchestration deliberately uses one call pattern:

```mojo
var index = SearchIndex(candidates^, language)
var page = index.search(query, case_mode, k)
```

This is an internal implementation seam shared by filtering and the picker,
not an installed or supported Mojo library API.

The index retains the complete exact match-ID set from the previous query. An
identical query or a scalar-safe query extension with the same case mode scans
only that set; backspace, arbitrary edits, and case-mode changes scan the full
corpus. This is exact for direct subsequence matching because extending a query
can only remove members. The optimization must remain disabled when future
phonetic expansion cannot prove the same variant-level monotonicity. Returned
rows use Hibana's exact score and scalar positions, total counts are computed
before truncation, and ties retain source order.

The index prepares candidate representations once, uses Hibana's score-only
path while scanning, and reconstructs positions only for final retained rows.
Each visible candidate contributes only its best compatible key. This keeps
the internal orchestration singular while avoiding per-query phonetic
generation and match-position allocation across the whole corpus.

The fuzzy scan itself has loop-carried pattern state and divergent Unicode
early exits. A measured folded SIMD cache regressed dense matching, so Hibana
keeps that kernel scalar. Parallelism is coarse across independent candidates;
SIMD is used in vector-friendly ecosystem kernels rather than added to a
dependency-bound fuzzy loop without evidence.

Yomi generates bounded typed Japanese, Chinese, and Korean candidate/query
keys. Yuragi merges the best compatible key match and projects generated-key
positions through Yomi's source mappings and Moji's scalar coordinates to the
original text. Language algorithms and mapping tables remain outside Yuragi.
`--lang auto` generates only direct keys; explicit language selection is needed
for phonetic expansion, so mixed-script behavior never depends on a heuristic
detector.

Shell integration is a deterministic generation boundary: `yuragi shell`
prints a script and never reads candidate input, probes the host, or edits a
profile. The generated script performs dependency checks when a binding runs,
prefers `fd`/`fdfind`, and documents its `find` or PowerShell fallback. Picker
stdout remains selection-only inside Ctrl-T, Ctrl-R, Alt-C, and `**` completion
workflows. `doctor` is similarly read-only; environmental warnings keep exit 0,
while an inability to resolve required process state is an exit-2 operational
error.

The configuration boundary currently resolves and reports one reserved path
with explicit-environment-over-XDG-over-HOME precedence. It deliberately does
not parse `config.toml`: the pinned Mojo 1.0 standard library supplies safe path
and file APIs but not a TOML parser, and a partial parser would create a false
compatibility contract.

`PLAN.md` defines the evidence required from Moji, Hibana, and Yomi before each
dependency is added. Dependencies must be pinned installable packages; release
builds do not reach into sibling source checkouts.

Yuragi `0.1.0` installs only its executable. Its modules, including
`SearchIndex`, remain application-internal and are not installed or supported
as a Mojo library package. Reusable algorithms, generated tables, platform
details, and backend implementations stay in their owning libraries. Generic
Mojo-native buffers, spans, strings, and collections are preferred over an
ecosystem-specific universal container.

## Data flow

Input validation occurs at the public boundary. Internal layers operate on
explicit typed values, produce deterministic outputs for deterministic inputs,
and report invalid state rather than silently replacing it with a default.
I/O, clocks, randomness, terminal queries, filesystem access, and accelerator
selection stay at explicit effect or backend boundaries. Standard input is
read through `FileDescriptor.read_bytes()` in bounded chunks and decoded as
UTF-8 once. This avoids the buffering and repeated-wrapper behavior of calling
Mojo's line-oriented `input()` repeatedly on a pipe.
