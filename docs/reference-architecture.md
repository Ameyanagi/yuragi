# Finder reference architecture

This document turns primary-source study of mature terminal fuzzy finders into
an executable architecture plan for Yuragi. It describes concepts and
contracts only. No reference implementation, scoring formula, source fragment,
or generated data is copied into Yuragi.

The target remains deliberately narrow:

- v0.1 is a deterministic, noninteractive CJK-aware Unix filter;
- v0.2 adds an interactive controller over the same search core;
- Moji, Hibana, Yomi, and MojoTUI retain their independent ownership
  boundaries; and
- `src/yuragi/` remains application-internal rather than becoming a supported
  library API.

## Research ledger

The references were shallow-cloned on 2026-08-20 under
`/Users/ryuichi/dev/reference-libraries/yuragi/`. The commit identifiers below
are the complete object IDs inspected, not moving tags or branches.

| Project | Inspected commit | License | Primary-source focus |
| --- | --- | --- | --- |
| [fzf](https://github.com/junegunn/fzf/tree/15f64c492a08f0840b81540c7d1de35737448086) | `15f64c492a08f0840b81540c7d1de35737448086` | MIT, copyright 2013–2026 Junegunn Choi | filter/interactive split, reader/search event coordination, revisions, streaming restrictions, output framing, exit status |
| [skim](https://github.com/lotabout/skim/tree/1b80cff3f72198da1ea334eef880a30327d37926) | `1b80cff3f72198da1ea334eef880a30327d37926` | MIT, copyright 2016 Jinzhou Zhang | shared reader/pool/matcher pipeline, filter gate, application event loop, original-versus-search text, test backend seam, output serialization |
| [fzy](https://github.com/jhawthorn/fzy/tree/34b88869d022e861da4846c4463aea3ddfb3ff30) | `34b88869d022e861da4846c4463aea3ddfb3ff30` | MIT, copyright 2014 John Hawthorn | minimal filter/TTY separation, stable input-order ties, parallel matching, match-position properties |

All three licenses were read from each pinned checkout's `LICENSE` file. The
clones are research inputs, not build inputs: they are not vendored, imported,
packaged, or required by Yuragi consumers.

### fzf findings

fzf makes the runtime event topology explicit: reader events restart the
matcher, terminal query events restart the matcher, and matcher progress/final
events update the terminal
([`src/core.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/core.go#L16-L40)).
It constructs the terminal only for interactive mode and enters a distinct
filter path otherwise
([`src/core.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/core.go#L181-L212),
[`src/core.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/core.go#L260-L352)).

Its streaming filter is enabled only when sorting, reverse order, synchronous
input, and benchmarking are absent. Otherwise fzf waits for ingestion, takes a
snapshot, scans it, then prints ordered results
([`src/core.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/core.go#L199-L212),
[`src/core.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/core.go#L260-L351)).
That distinction is directly relevant to Yuragi: streaming record framing does
not make globally ranked output streamable.

The interactive coordinator uses read/search events and input revisions so a
new candidate snapshot or query invalidates incompatible search work
([`src/constants.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/constants.go#L60-L76),
[`src/core.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/core.go#L378-L480)).
The reader owns source selection and publishes coalesced read-new/read-finished
events rather than letting the terminal read candidate input
([`src/reader.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/reader.go#L20-L88),
[`src/reader.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/reader.go#L124-L151)).

fzf also keeps delimiter and process-result policies explicit. It has
independent NUL input/output options and distinct success, no-match, error, and
interrupt statuses
([`src/options.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/options.go#L3039-L3056),
[`src/constants.go`](https://github.com/junegunn/fzf/blob/15f64c492a08f0840b81540c7d1de35737448086/src/constants.go#L71-L76)).
Yuragi should make the same policies explicit, but need not choose the same
values.

### skim findings

skim routes both operating modes through a reader, item pool, matcher, and
processed-result model. Filter mode waits until reading and matching finish and
then returns without entering the TUI
([`src/skim.rs`](https://github.com/lotabout/skim/blob/1b80cff3f72198da1ea334eef880a30327d37926/src/skim.rs#L431-L467)).
The interactive loop multiplexes terminal events, matcher restart intervals,
and notifications that new items are available
([`src/skim.rs`](https://github.com/lotabout/skim/blob/1b80cff3f72198da1ea334eef880a30327d37926/src/skim.rs#L622-L705)).
Its reader owns collection and cancellation while appending batches to the
item pool
([`src/reader.rs`](https://github.com/lotabout/skim/blob/1b80cff3f72198da1ea334eef880a30327d37926/src/reader.rs#L37-L78),
[`src/reader.rs`](https://github.com/lotabout/skim/blob/1b80cff3f72198da1ea334eef880a30327d37926/src/reader.rs#L111-L163)).

The default terminal backend writes to buffered stderr, preserving stdout for
the selected data, and the backend has a replaceable construction seam used by
tests
([`src/tui/backend.rs`](https://github.com/lotabout/skim/blob/1b80cff3f72198da1ea334eef880a30327d37926/src/tui/backend.rs#L45-L80)).
Final selection/state is collected separately from CLI serialization
([`src/output.rs`](https://github.com/lotabout/skim/blob/1b80cff3f72198da1ea334eef880a30327d37926/src/output.rs#L10-L38),
[`src/skim.rs`](https://github.com/lotabout/skim/blob/1b80cff3f72198da1ea334eef880a30327d37926/src/skim.rs#L535-L575)).
This is a strong precedent for a MojoTUI adapter that renders application state
without owning Yuragi's stdout or exit policy.

skim's item model distinguishes original output text from transformed search
or display text. Its project architecture records ordered ingestion after
parallel parsing and the coordinate remapping required for transformed display
([`ARCHITECTURE.md`](https://github.com/lotabout/skim/blob/1b80cff3f72198da1ea334eef880a30327d37926/ARCHITECTURE.md#L418-L469)).
Yuragi needs the same separation at a more demanding boundary: Moji/Yomi source
mappings must lead match positions back to exact original CJK ranges.

### fzy findings

fzy is a useful deliberately small counterexample to feature-heavy finders.
Its entry point sends both `--show-matches` and interactive operation through
the same choices/search model, while terminal I/O is opened only in the
interactive branch
([`src/fzy.c`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/src/fzy.c#L16-L70)).
Its ranking comparator orders score descending and resolves equal scores by
the original contiguous input position
([`src/choices.c`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/src/choices.c#L18-L37)).
Parallel workers produce sorted runs that are merged into one result sequence
([`src/choices.c`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/src/choices.c#L145-L313)).

The interactive controller recalculates the choices when the query changes and
draws positions returned by the matcher
([`src/tty_interface.c`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/src/tty_interface.c#L33-L132)).
Its property tests independently require match positions to increase and to
identify the expected characters
([`test/test_properties.c`](https://github.com/jhawthorn/fzy/blob/34b88869d022e861da4846c4463aea3ddfb3ff30/test/test_properties.c#L84-L159)).
Yuragi adopts the stable-order and invariant-testing ideas; fuzzy score and
position algorithms remain Hibana's responsibility.

## Decisions derived from the references

### Adopt

- One candidate, preparation, matching, and ranking path serves both modes.
- Noninteractive and interactive execution have separate controllers and
  effect boundaries.
- Every candidate receives a monotonic source index before parallel or
  asynchronous work begins.
- Search work is tagged with a generation; results from a stale generation are
  discarded rather than rendered or emitted.
- Original output text is distinct from direct, normalized, phonetic, and
  display representations.
- Candidate ingestion, terminal input, matching, rendering, and stdout
  serialization have explicit ownership.
- Terminal rendering uses stderr or a controlling-terminal backend, leaving
  stdout byte-exact for accepted candidates.
- Output serialization accepts a sink so it can be tested without a terminal
  or process.
- Streaming is a contract chosen per mode, not an automatic consequence of
  chunked reads.

### Reject for v0.1 and the first interactive slice

- copying any fzf, skim, or fzy scoring algorithm;
- a second Yuragi matcher used only by the TUI;
- built-in filesystem walking or implicit default commands;
- preview subprocesses, command reload, arbitrary action-binding languages,
  embedded servers, or remote control;
- multi-selection, ANSI interpretation, field-expression transforms, history,
  popup/tmux orchestration, and shell-completion generation;
- a public embeddable Yuragi library surface; and
- SIMD, worker pools, cancellation threads, or incremental top-K before a
  benchmark and the owning dependency contracts justify them.

These are scope decisions, not claims that the reference features are poor.
They keep v0.1 centered on the CJK-aware filter that proves the ecosystem.

## Target layers

```text
process boundary
  main / argv / status / diagnostics / signal policy
                 |
                 v
mode controllers +------------------------------+
  FilterController                              |
  InteractiveController (later)                 |
                 |                              |
                 v                              v
application core                           effect ports
  CandidateFramer / CandidateStore          input bytes
  QueryPreparation / SearchSession          output bytes
  RankingPolicy / LanguagePolicy            terminal events
                 |                          clock/cancellation
                 v
dependency adapters
  MojiAdapter  YomiAdapter  HibanaAdapter  MojoTUIAdapter (later)
                 |             |               |
                 +-------------+---------------+
                               v
                    independently packaged libraries
```

The arrows point downward only. Moji, Hibana, Yomi, and MojoTUI must not import
Yuragi or implement its language, ranking, output, or process policy.

### Process boundary

`main.mojo` owns argv conversion, help/version precedence, stdin/stdout/stderr,
signal-to-status translation, and final exit. It parses and validates before
reading stdin. It does not score candidates, infer a language, or render a
widget.

### Mode controllers

`FilterController` runs one finite request to completion. It is the only v0.1
controller. `InteractiveController` later applies events to session state and
requests searches/renders; it must reuse the same preparation and ranking
functions rather than duplicating them.

### Application core

The core owns candidate identity, preparation orchestration, the definition of
one search request, deterministic cross-representation ranking, and the choice
of output candidates. It is synchronous and deterministic first. Background
execution is an adapter/effect concern added only when the state machine can
reject stale results.

### Dependency adapters

Adapters should be thin application modules around installed package APIs, not
alternate implementations:

| Adapter | Receives | Returns | Must not own |
| --- | --- | --- | --- |
| Moji | original candidate/query text | safe text views, coordinates, transformed-to-source mappings | fuzzy scores, CJK readings, CLI policy |
| Yomi | explicit `zh`, `ja`, or `ko` request plus Moji-compatible text | ordered phonetic representations with exact source mappings | `auto` detection, cross-view ranking, matching |
| Hibana | prepared query and one searchable view | matched state, score, ordered positions/top-K result under a named scheme | language detection, phonetic conversion, output text |
| MojoTUI | immutable render model and input/resize events | buffer updates and typed terminal events | candidates, matching, ranking, stdout, process exit |

Release builds depend on pinned installable packages. They never reach into
sibling source checkouts. Adapter contract tests should run against the same
artifacts that the Conda recipe installs.

## Candidate ingestion and framing

### v0.1 baseline

The current whole-stream baseline is correct and remains the first executable
contract:

1. read arbitrary byte chunks from stdin;
2. aggregate them before UTF-8 decoding so one scalar may span reads;
3. validate UTF-8 at the input boundary;
4. split only on LF;
5. remove one CR only when it immediately precedes LF;
6. preserve blank records and an unterminated final record;
7. do not invent a final record for a trailing delimiter; and
8. assign `source_index` in record order.

The original candidate string is immutable application data. Search and
display transformations never replace it.

### Bounded framer seam

A later `CandidateFramer` may keep only the unfinished byte suffix across
reads, decode complete records, and yield batches. Its tests must force UTF-8
scalars and CRLF pairs across every chunk boundary of interest. Decoding each
read independently is forbidden.

Framing may stream even when selection cannot. Globally sorted filter output
must wait for input completion unless Hibana exposes a proven bounded top-K
contract and the user requested a finite limit. An eventual explicitly
unsorted/input-order mode could emit matches as records arrive, but it is a new
CLI contract and is not v0.1.

NUL-delimited input/output is deferred. If introduced, it uses explicit,
independent `--read0` and `--print0` choices with every combination tested; it
is never auto-detected.

## Search, language, and ranking ownership

Each prepared candidate contains its immutable source identity and an ordered
set of searchable views:

```text
PreparedCandidate
  candidate: Candidate(source_index, original_text)
  views:
    direct(original/search-safe Moji view)
    phonetic(language, transformed text, source mapping) ...
```

Yuragi owns which views exist for a CLI request. Moji owns their coordinate and
source-mapping primitives. Yomi owns language-specific transformations. Hibana
owns whether and how one view matches.

`--lang zh`, `ja`, or `ko` requests only that language's Yomi views plus the
direct view. `--lang auto` remains Yuragi policy: script detection,
mixed-script handling, fallback, and representation order must be documented
with fixtures before it is enabled. Yomi must not expose an application-level
`auto` answer on Yuragi's behalf.

For v0.1, candidate order is defined by one explicit total-order key:

1. matched candidates before unmatched candidates (unmatched candidates are
   omitted from filter output);
2. Hibana score descending under one named matching scheme;
3. representation priority only when the best scores are exactly equal,
   direct before the ordered language-specific views; and
4. `source_index` ascending as the final tie-break.

For one candidate, the best representation uses the same score and
representation-priority ordering. Comparing direct and phonetic scores is
allowed only after Hibana documents that scores produced by the selected
scheme are comparable across those views. If they are not comparable, the
ranking-policy issue must choose and test an explicit normalization or tiered
policy before Yomi integration; Yuragi must not silently compare unlike
scores.

Match positions remain attached to the winning view and map through Moji/Yomi
to ordered exact original ranges. A bounding span is insufficient for
discontiguous matches. Source mappings affect highlighting, never output text
or the stable source-index tie-break.

## Minimal internal application API

The names below describe responsibilities, not committed Mojo spelling or a
public import surface:

```text
AppOptions
  mode, query, language, framing, output framing

Candidate
  source_index, original_text

PreparedCandidate
  candidate identity, ordered searchable views

SearchRequest
  generation, prepared query, language policy, optional result limit

CandidateMatch
  candidate identity, score, winning view, match positions/source ranges

SearchSnapshot
  generation, ordered matches, input_complete

SearchSession
  prepare candidates, execute one request, apply only current-generation result

OutputEncoder
  write original candidates to a supplied byte sink under the selected framing
```

The only v0.1 command shape remains:

```text
yuragi --filter QUERY [--lang auto|zh|ja|ko]
```

Absence of `--filter` selects the later interactive controller; until that
controller ships, it remains an explicit usage/unavailable error. No internal
type above is re-exported from `yuragi.__init__` as a supported library API.

## Noninteractive controller

The finite filter path is:

```text
parse/validate argv
  -> read and frame candidates
  -> prepare direct/language views
  -> execute Hibana matches
  -> apply Yuragi total ordering
  -> encode original candidates
  -> translate result/error to process status
```

An empty query remains identity selection in source order. A non-empty query
does not gain a placeholder substring fallback while dependencies are absent.
The controller contains no terminal setup and is testable with supplied byte
input and output/error sinks.

## Interactive controller

Interactive mode adds state and effects around the same `SearchSession`:

```text
candidate batch/input finished/input failed ----+
query changed/key/resize/accept/cancel ----------+--> reduce event
search finished(generation) ---------------------+        |
                                                          v
                                             state + requested effects
                                             search / render / exit
```

The minimum typed event set is:

- `CandidatesArrived(batch)`;
- `InputFinished` and `InputFailed(error)`;
- `QueryChanged(text)`;
- `SearchFinished(generation, snapshot)` and `SearchFailed(generation, error)`;
- `Key`, `Resize`, and later paste/mouse events as exposed by MojoTUI;
- `Accept`, `Cancel`, and `Interrupted`.

Every query change or semantically relevant candidate update increments the
search generation. Only a result whose generation equals the current state may
replace visible results. Cancellation may save work, but generation checks are
the correctness mechanism. A deterministic synchronous executor and fake
event source come before background matching.

MojoTUI renders a snapshot of application state and returns typed terminal
events. It does not mutate the candidate store, call Hibana/Yomi, select shell
commands, or write the accepted candidate to stdout.

## Shell, output, and exit contracts

- stdin is candidate data; terminal keystrokes later come from a controlling
  terminal through the MojoTUI/backend boundary;
- stdout contains only encoded original candidate records;
- stderr contains diagnostics and, later, terminal rendering;
- help and version use stdout and do not read stdin;
- option errors are resolved before stdin is read;
- filter output always ends each emitted candidate with the configured output
  delimiter; and
- transformed, normalized, or phonetic text is never emitted in place of the
  original candidate.

The v0.1 status contract remains:

| Status | Meaning |
| --- | --- |
| `0` | valid help/version or a successfully executed filter, including zero matches |
| `1` | input, output, or internal/operational failure |
| `2` | invalid usage or an explicitly unavailable mode/dependency gate |

This intentionally rejects fzf's status 1 for an ordinary no-match filter:
Yuragi's existing status 1 is operational failure, while a valid Unix filter
that selects no records completed successfully. The CLI fixture must lock that
decision before non-empty matching lands.

Interactive mode may later reserve status 130 for user cancellation or an
interrupt signal. That addition requires signal and terminal-cleanup tests and
must not change filter no-match behavior. A broken output pipe is an output
failure under status 1; its diagnostic policy should be locked by a compiled
CLI test against the behavior available in the pinned Mojo standard library.

Shell integration is documentation and thin shell code around this process
contract. v0.1 does not execute a shell, infer a default source, evaluate
candidate text, or interpolate a selected value into a command.

## Verification plan

### Unit and reference tests

- option uniqueness, precedence, language values, and unavailable-mode gates;
- LF/CRLF/blank/final-record framing over controlled arbitrary chunks;
- invalid UTF-8 before, within, and after a record delimiter;
- monotonically assigned source indices and exact original-text preservation;
- language-policy fixtures for ASCII, zh, ja, ko, and mixed scripts;
- adapter fixtures pinned to documented Moji/Yomi/Hibana coordinates;
- direct/phonetic score comparison and representation ties;
- stable ordering for equal score under reordered worker completion;
- exact discontiguous source ranges from winning representations;
- stale-generation rejection and idempotent input-finished/error transitions;
- output encoding into an in-memory byte sink; and
- state-machine accept, cancel, resize, input failure, and search failure paths.

Ranking tests need an independent small oracle that enumerates expected
ordering keys; they must not reuse the production sort helper to calculate the
expected sequence.

### Compiled CLI and package tests

- empty input, empty query, no match, blank candidates, CJK, and stable ties;
- exact stdout/stderr/status for help, version, usage, invalid UTF-8, read
  failure, output failure where controllable, and unavailable interactive mode;
- multibyte UTF-8 split across controlled unit-test chunks plus a nominal
  executable-buffer-boundary fixture that does not assume full OS reads;
- installed executable smoke tests using only packaged dependencies; and
- clean-source Conda build on every declared platform.

### Interactive tests

- MojoTUI TestBackend buffer snapshots for initial, searching, results, empty,
  error, resized, and selected states;
- a fake event source/sink with deterministic sequences;
- stale search completion after a newer query;
- candidates arriving while a search is in flight;
- accept emits exactly one original candidate after terminal restoration; and
- cancel/input failure restores the terminal and emits no candidate.

### Benchmark methodology

Record CPU, OS, exact Mojo and dependency versions, compiler options, revision
and dirty state, dataset provenance/digest, warmup, iterations, statistic, and
the exact command. Commit workloads and methodology, not timeless performance
claims.

Measure these stages separately:

1. byte ingestion and record framing;
2. Moji view/mapping preparation;
3. Yomi representation generation by explicit language;
4. Hibana matching without Yuragi sorting;
5. Yuragi ranking/top-K orchestration; and
6. complete noninteractive and, later, query-to-render latency.

Use 100, 10,000, and 1,000,000 candidate corpora with empty, short, long, and
no-match queries; ASCII paths; combining marks and emoji; language-specific
CJK; and mixed scripts. Dataset licenses and checksums belong in provenance
documentation. Performance changes must preserve the same result/order/mapping
fixtures.

## Dependency-ordered issue plan

Each issue produces reviewable evidence and leaves later work blocked until its
exit criteria pass.

| Order | Issue | Depends on | Exit evidence |
| --- | --- | --- | --- |
| 1 | `YRA-001` lock this reference architecture and the v0.1 CLI/status/ranking decisions | current foundation | reviewed document; reference SHAs/licenses; locked check/package |
| 2 | `YRA-002` extract internal source/framer/output-sink contracts without changing CLI behavior | YRA-001 | controlled chunk/framing tests, byte-sink tests, unchanged compiled CLI fixtures |
| 3 | `YRA-003` integrate a pinned installable Moji text-view/source-coordinate adapter | Moji gate A, YRA-002 | installed-package smoke, pathological Unicode mapping fixtures, no sibling imports |
| 4 | `YRA-004` integrate Hibana for deterministic direct-view non-empty filtering | Hibana gate B, YRA-003 | matcher/reference tests, empty/no-match/stable-tie CLI fixtures, no Yomi logic |
| 5 | `YRA-005` lock Yuragi's total-order and cross-representation score contract | YRA-004 and documented Hibana comparability | independent ordering oracle, representation/source-index tie fixtures |
| 6 | `YRA-006` integrate pinned Yomi explicit `zh`, `ja`, and `ko` adapters | Yomi gate C, YRA-005 | language fixtures, exact source ranges, original-text output, provenance review |
| 7 | `YRA-007` implement and document Yuragi-owned `--lang auto` | YRA-006 | ASCII/CJK/mixed-script decision table and CLI/reference tests |
| 8 | `YRA-008` close v0.1 noninteractive process/package contracts | YRA-007 | motivating `bjdx` fixture, error/output/status matrix, locked CI, clean package build |
| 9 | `YRA-009` benchmark and decide bounded framer/store/top-K work | YRA-008 and stable Hibana lifetime/top-K API | reproducible stage benchmarks and an accept/reject design decision; no semantic drift |
| 10 | `YRA-010` add the deterministic interactive state machine with fake effects | YRA-008 | generation/stale-result/event-transition tests; no terminal dependency yet |
| 11 | `YRA-011` add MojoTUI as a pinned rendering/input adapter | MojoTUI gate, YRA-010 | TestBackend snapshots, resize/accept/cancel/cleanup tests, stdout remains clean |
| 12 | `YRA-012` specify shell integrations and evaluate previews/configuration separately | YRA-011 | shell-specific byte/status fixtures and independently scoped accepted designs |

Filesystem traversal, reload, remote control, multi-select, advanced actions,
and native preview processes remain outside this issue sequence. Each requires
its own product case after Yuragi proves the core ecosystem path.
