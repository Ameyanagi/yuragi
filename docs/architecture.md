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
candidate framing, output framing, direct-text Hibana ranking, exact pre-limit
match counts, bounded top-K rows, and an inline MojoTUI picker. An empty query is
identity selection. The picker and filter share the same ranking path; retained
rows never stand in for the total match count, and cursor identity follows the
source candidate across query changes.

The empty interactive query is represented as a lazy identity view. Its exact
cardinality and cursor IDs come directly from the owned `SearchIndex`; only the
visible viewport is copied into MojoTUI `ListItem` values. The host receives a
model copy because its fallible terminal constructor cannot transactionally
return a moved model on failure; lazy identity rows keep that copy from
duplicating one ranked row per candidate.

## Search state and ranking contracts

The interactive path owns a `SearchIndex` whose public surface is deliberately
small:

```mojo
var index = SearchIndex(candidates^)
var page = index.search(query, case_mode, k)
```

The index retains the complete exact match-ID set from the previous query. An
identical query or a scalar-safe query extension with the same case mode scans
only that set; backspace, arbitrary edits, and case-mode changes scan the full
corpus. This is exact for direct subsequence matching because extending a query
can only remove members. The optimization must remain disabled when future
phonetic expansion cannot prove the same variant-level monotonicity. Returned
rows use Hibana's exact score and scalar positions, total counts are computed
before truncation, and ties retain source order.

The installed Hibana package currently exposes only the allocation-bearing
matcher, so this first index improves repeated/refined scans but is not yet a
prepared corpus. Hibana source now has three opt-in building blocks for the
next package release:

- exact allocation-free score-only matching plus caller-owned final positions;
- `HYBRID` ranking, which has exact membership, counts, finalist scores, and
  positions but approximate top-B candidate selection;
- synchronous parallel `EXACT` ranking with deterministic shard merging.

`EXACT` and `HYBRID` remain explicit policies. A fixed hybrid shortlist must
never be described as exact top-k equivalence. The product path will consume
these APIs only from immutable multi-platform packages; it does not import
sibling source trees or replace a hosted artifact in place.

The fuzzy scan itself has loop-carried pattern state and divergent Unicode
early exits. A measured folded SIMD cache regressed dense matching, so Hibana
keeps that kernel scalar. Parallelism is coarse across independent candidates;
SIMD is used in vector-friendly ecosystem kernels rather than added to a
dependency-bound fuzzy loop without evidence.

Yomi phonetic key integration remains a package-release gate. Yuragi will index
one visible candidate into bounded typed search keys, merge the best compatible
key match, and project only visible/accepted generated-key positions back to
the original text. Language algorithms and mapping tables remain outside
Yuragi.

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

Yuragi does not export a supported library surface. Its modules remain
application-internal; reusable algorithms, generated tables, platform details,
and backend implementations stay in their owning libraries. Generic
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
