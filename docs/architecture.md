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

Planned implementation areas: options, configuration, input/output, search candidate and ranking orchestration, later UI screens, and shell adapters.

The package root exports only the small documented public surface. Algorithms,
generated tables, platform details, and backend implementations remain in
their owning modules. Generic Mojo-native buffers, spans, strings, and
collections are preferred over an ecosystem-specific universal container.

## Data flow

Input validation occurs at the public boundary. Internal layers operate on
explicit typed values, produce deterministic outputs for deterministic inputs,
and report invalid state rather than silently replacing it with a default.
I/O, clocks, randomness, terminal queries, filesystem access, and accelerator
selection stay at explicit effect or backend boundaries.
