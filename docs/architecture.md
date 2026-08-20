# Architecture

Yuragi owns Command-line orchestration, candidate ingestion, ranking policy, output, configuration, shell integration, and later interactive UI.

## Dependency boundary

Allowed ecosystem dependencies: Hibana, Yomi, and Moji for the first useful prototype; MojoTUI only when interactive mode begins.
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

        MojoTUI enters only with interactive mode
```

The implemented foundation includes options, whole-stream UTF-8 ingestion,
candidate framing, output framing, and an explicit matching integration gate.
The application accepts an empty query as identity selection. It rejects a
non-empty query until the ecosystem match path is available, preventing a
placeholder algorithm from becoming an accidental compatibility contract.

`PLAN.md` defines the evidence required from Moji, Hibana, and Yomi before each
dependency is added. Dependencies must be pinned installable packages; release
builds do not reach into sibling source checkouts.

`docs/reference-architecture.md` derives the target filter/interactive split,
streaming rules, dependency adapters, ranking and language ownership, process
contracts, verification matrix, and dependency-ordered issues from pinned
primary finder sources.

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
