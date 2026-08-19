# Yuragi

> **Experimental — API not yet released.**

A CJK-aware fuzzy finder written in Mojo.

## Scope

Yuragi composes the ecosystem into an end-user fuzzy-finder application rather than exporting foundation algorithms.

The first implementation milestone is intentionally narrow: accept candidates on standard input and provide deterministic noninteractive --filter output using CJK phonetic representations before adding an interactive terminal UI.
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

The current executable only reports its experimental scaffold status. It does
not yet implement candidate filtering or claim a released CLI contract.

## Repository map

- `src/yuragi/`: application source and executable entry point
- `tests/`: TestSuite unit, reference-value, and invariant tests
- `examples/`: small compilable usage programs
- `benchmarks/`: reproducible methodology and later benchmark programs
- `docs/`: architecture, design, compatibility, roadmap, and release policy
- `conda.recipe/`: local Rattler build recipe

See [the architecture](docs/architecture.md), [design principles](docs/design.md),
and [roadmap](docs/roadmap.md) before proposing a new dependency or feature.

## License

Licensed under either Apache-2.0 or MIT, at your option.
