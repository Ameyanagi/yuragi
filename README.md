# Yuragi

> **Experimental — API not yet released.**

A CJK-aware fuzzy finder written in Mojo.

## Scope

Yuragi composes the ecosystem into an end-user fuzzy-finder application rather than exporting foundation algorithms.

The current implementation accepts candidates on standard input and provides
both an inline interactive picker and deterministic noninteractive `--filter`
output through direct fuzzy matching. Phonetic representations remain gated on
Yomi.
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

The executable implements validated options, UTF-8 stdin ingestion, stable
candidate framing, deterministic stdout, and an inline interactive application
adapter. An empty filter query is an identity filter:

```sh
printf "北京大学\nnotes\n" | pixi run yuragi --filter ''
```

Non-empty queries now rank candidates through the installed Hibana Conda
package:

```sh
printf 'apple\nbanana\n' | pixi run yuragi --filter ba
banana
```

Add `--explain` to print one stable, newline-terminated diagnostic line per
retained match, in ranked order:

```text
RANK<TAB>SCORE<TAB>KEY<TAB>POSITIONS<TAB>TEXT
```

`RANK` is one-based, `SCORE` is Hibana's integer score, `KEY` is currently
`original`, and `POSITIONS` contains comma-separated zero-based Unicode scalar
indices. `TEXT` is the unmodified candidate. TEXT is last so the first four
fields are tab-free and a consumer can split on the first four tabs even when
TEXT itself contains tabs.

```sh
printf 'apple\nbanana\n' | pixi run yuragi --filter ba --explain
1	390	original	0,1	banana
```

Use `--limit N` to emit at most the best N candidates. A non-empty query that
matches nothing exits with status 1 and writes no candidate output. Phonetic
language matching still awaits Yomi; Yuragi does not duplicate CJK logic. See
[PLAN.md](PLAN.md) for the remaining dependency gates and exact v0.1 acceptance
criteria.

Use `--read0` and `--print0` for NUL framing when filenames can contain
newlines. Smart case is the default; `--ignore-case` and `--no-ignore-case`
provide hard ASCII case-sensitivity overrides.

## Interactive

Omit `--filter` to open a fixed-height picker inline on the controlling terminal:

```sh
ls | yuragi
```

Candidate input still comes only from standard input. The picker writes its UI
directly to the controlling terminal, while stdout remains reserved for the
accepted candidate. Its single fixed keymap has no `--bind` DSL:

| Keys | Action |
| --- | --- |
| Enter | Accept the cursor candidate |
| Esc, Ctrl-C | Abort |
| Down, Ctrl-N | Move to the next candidate |
| Up, Ctrl-P | Move to the previous candidate |
| Backspace | Erase the last query grapheme |

Exit codes are `0` for a successful match or acceptance, `1` when there is no
match or nothing to accept, `2` for usage or operational errors, and `130` for
interactive abort. Only a successful selection is written to stdout.

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
