# Yuragi

> **Experimental — API not yet released.**

A CJK-aware fuzzy finder written in Mojo.

## Scope

Yuragi composes the ecosystem into an end-user fuzzy-finder application rather than exporting foundation algorithms.

The first implementation milestone is intentionally narrow: accept candidates
on standard input and provide deterministic noninteractive `--filter` output
through direct fuzzy matching before adding phonetic representations or an
interactive terminal UI.
The project is independently installable and does not require any application
from the wider ecosystem.

## Development

Install [Pixi](https://pixi.sh/), then run:

```sh
pixi install --locked
pixi run check
pixi run example
```

The exact stable Mojo compiler and all development dependencies are captured in
`pixi.lock`. Runtime and library code is Mojo-first and pure Mojo wherever
practical. Build-time data generation may use another language when justified,
but generated outputs must be deterministic, checksum-pinned, licensed, and
documented.

## Application package

Yuragi installs an executable named `yuragi`. Its internal Mojo modules live
under `src/yuragi/`; they are application implementation details rather than a
separately supported library API. The Conda distribution is also named
`yuragi`.

The executable now implements the first noninteractive application boundary:
validated options, UTF-8 stdin ingestion, stable candidate framing, and
deterministic stdout. An empty query is an identity filter:

```sh
printf "北京大学\nnotes\n" | pixi run yuragi --filter ''
```

Non-empty queries now rank candidates through the installed Hibana Conda
package:

```sh
printf 'apple\nbanana\n' | pixi run yuragi --filter ba
banana
```

Use `--limit N` to emit at most the best N candidates. A non-empty query that
matches nothing exits with status 1 and writes no candidate output. Explicit
phonetic language matching still awaits Yomi; Yuragi does not duplicate CJK
logic. See [PLAN.md](PLAN.md) for the remaining dependency gates and exact v0.1
acceptance criteria.

## Repository map

- `src/yuragi/`: application source and executable entry point
- `tests/`: TestSuite unit, reference-value, and invariant tests
- `examples/`: small compilable usage programs
- `benchmarks/`: reproducible methodology and later benchmark programs
- `docs/`: architecture, design, compatibility, roadmap, and release policy
- `conda.recipe/`: local Rattler build recipe
- `PLAN.md`: dependency-gated implementation plan and acceptance evidence

See [the architecture](docs/architecture.md), [design principles](docs/design.md),
and [roadmap](docs/roadmap.md) before proposing a new dependency or feature.

## License

Licensed under either Apache-2.0 or MIT, at your option.
