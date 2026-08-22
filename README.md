# Yuragi

> **Experimental — API not yet released.**

A CJK-aware fuzzy finder written in Mojo.

## Scope

Yuragi composes the ecosystem into an end-user fuzzy-finder application rather than exporting foundation algorithms.

The current implementation accepts candidates on standard input and provides
both an inline interactive picker and deterministic noninteractive `--filter`
output through direct fuzzy matching. Interactive query extensions reuse the
previous complete exact match set through a persistent `SearchIndex`; arbitrary
edits fall back to a full scan. Phonetic representations remain gated on the
first immutable Yomi package release.
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
accepted candidates. Its single fixed keymap has no `--bind` DSL:

- `--query STR`/`-q STR` pre-fills the prompt and computes its initial ranking.
- `--select-1`/`-1` prints and accepts a sole initial match without opening the
  picker.
- `--exit-0`/`-0` exits with status 1 and empty stdout when the initial query
  has no matches, without opening the picker.
- `--multi`/`-m` enables marking several candidates. Enter accepts every mark
  in source order, or the cursor candidate when nothing is marked.

The two automation flags compose with each other and evaluate the `--query`
seed when supplied. All four flags are interactive-only and are usage errors
with `--filter`.

| Keys | Action |
| --- | --- |
| Enter | Accept marks, or the cursor candidate when no marks exist |
| Esc, Ctrl-C | Abort |
| Down, Ctrl-N | Move to the next candidate |
| Up, Ctrl-P | Move to the previous candidate |
| TAB | With `--multi`, toggle the cursor mark and move down |
| Shift-TAB | With `--multi`, toggle the cursor mark and move up |
| Backspace | Erase the last query grapheme |

Marks follow candidate source identities, so they survive query refinement
even while a marked candidate is absent from the current matches. TAB and
Shift-TAB are inert without `--multi`.

An empty prompt is a lazy identity view: it preserves the exact full count and
source order but materializes only the rows visible in the terminal. This keeps
ranked-row startup and redraw work bounded by the viewport instead of the
corpus size. `--limit N` bounds selectable interactive rows while the counter
retains the exact untruncated match count.

Exit codes are `0` for a successful match or acceptance, `1` when there is no
match or nothing to accept, `2` for usage or operational errors, and `130` for
interactive abort. Only a successful selection is written to stdout.

## Shell workflows and diagnostics

Generate a shell integration on stdout, then load it with the shell's normal
evaluation mechanism:

```sh
eval "$(yuragi shell bash)"
eval "$(yuragi shell zsh)"
yuragi shell fish | source
```

PowerShell uses `Invoke-Expression ((yuragi shell powershell) -join "`n")`.
The generated scripts provide Ctrl-T file selection, Ctrl-R history selection,
Alt-C directory selection, and fzf-style `**` path completion. They prefer
`fd`, accept Debian's `fdfind` name, and fall back to `find` on POSIX shells or
`Get-ChildItem` in PowerShell. Each binding checks Yuragi and its path source at
the time it runs. Set `YURAGI_BIN` when the executable is not named `yuragi` or
is not discoverable through the shell's normal command lookup.

Run `yuragi doctor` for a read-only report of the resolved configuration path,
shell hint, and available path finder. Missing optional shell hints and finders
are warnings and do not make `doctor` fail; an operational failure to resolve
the configuration location exits 2.

`yuragi config path` prints the reserved configuration path. Resolution order
is `YURAGI_CONFIG_FILE`, then `XDG_CONFIG_HOME/yuragi/config.toml`, then
`HOME/.config/yuragi/config.toml`. Configuration values are not loaded in this
release: Mojo 1.0 provides safe filesystem I/O but no TOML parser, and Yuragi
does not claim compatibility through an incomplete hand-written subset.

## Repository map

- `src/yuragi/`: application source and executable entry point
- `tests/`: TestSuite unit, reference-value, and invariant tests
- `examples/`: small compilable usage programs
- `benchmarks/`: reproducible fair-search and profiler-oriented benchmarks
- `docs/`: architecture, design, compatibility, roadmap, and release policy
- `conda.recipe/`: local Rattler build recipe
- `PLAN.md`: dependency-gated implementation plan and acceptance evidence

See [the architecture](docs/architecture.md), [design principles](docs/design.md),
and [roadmap](docs/roadmap.md) before proposing a new dependency or feature.

## License

Licensed under either Apache-2.0 or MIT, at your option.
