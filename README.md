# Yuragi

> **Experimental — pre-1.0 command-line contracts may still evolve.**

A CJK-aware fuzzy finder written in Mojo.

## Scope

Yuragi composes the ecosystem into an end-user fuzzy-finder application rather
than exporting foundation algorithms.

The current implementation accepts candidates on standard input and provides
both an inline interactive picker and deterministic noninteractive `--filter`
output. Internally, both workflows construct one prepared `SearchIndex` and
call its one search method. This is an application implementation detail, not
an installed Mojo library API. Explicit `ja`, `zh`, and `ko` modes add bounded
Yomi phonetic keys and map generated-key matches back to the original
candidate. `auto` deliberately means direct-text search only; it does not guess
a language from mixed Unicode input.
The project is independently installable and does not require any application
from the wider ecosystem.

## Install

Install the published application with Pixi:

```sh
pixi global install "yuragi==0.1.0" \
  --channel https://ameyanagi.github.io/mojo-channel \
  --channel https://conda.modular.com/max \
  --channel conda-forge
```

This puts a `yuragi` binary on PATH, so `ls | yuragi` works as typed.

### From source

Install [Pixi](https://pixi.sh/), then run:

```sh
pixi install --locked
pixi run check
pixi run example
```

In a development checkout, the equivalent of `ls | yuragi` is
`ls | pixi run yuragi`, which rebuilds the binary first. Internal application
modules compile with
`pixi run mojo run -I src examples/basic.mojo`.

The exact stable Mojo compiler and all development dependencies are captured in
`pixi.lock`. Runtime and library code is Mojo-first and pure Mojo wherever
practical. Build-time data generation may use another language when justified,
but generated outputs must be deterministic, checksum-pinned, licensed, and
documented.

## Quickstart

Pipe candidates to the executable and give `--filter` one query:

```sh
printf 'apple\nbanana\nbar\n' | yuragi --filter ba
```

Expected output:

```text
banana
bar
```

Yuragi `0.1.0` installs and supports one application executable, not a Mojo
library package. Its `SearchIndex` and other modules remain internal. Hibana,
Moji, Yomi, and MojoTUI provide the reusable foundation APIs.

Mojo programs integrate with Yuragi through ordinary UTF-8 records, so no
application-specific API is required:

```mojo
def main():
    print("北京大学")
    print("notes")
```

Build that producer and pipe it into `yuragi --lang zh --filter bjdx` to select
the original `北京大学` record.

## Application package

Yuragi installs an executable named `yuragi`. Its internal Mojo modules live
under `src/yuragi/`; the distribution does not install or support them as an
importable Mojo package. The Conda distribution is also named `yuragi`.

The executable implements validated options, buffered UTF-8 stdin ingestion,
stable candidate framing, deterministic stdout, and an inline interactive
application adapter. Invalid UTF-8 bytes are replaced with U+FFFD rather than
failing. An empty filter query is an identity filter:

```sh
printf "北京大学\nnotes\n" | pixi run yuragi --filter ''
```

Non-empty queries rank candidates through the installed Hibana package:

```sh
printf 'apple\nbanana\n' | pixi run yuragi --filter ba
banana
```

Add `--explain` to print one stable, newline-terminated diagnostic line per
retained match, in ranked order:

```text
RANK<TAB>SCORE<TAB>KEY<TAB>POSITIONS<TAB>TEXT
```

`RANK` is one-based, `SCORE` is the weighted Hibana score, and `KEY` identifies
the winning direct or language-specific key. `POSITIONS` always contains
comma-separated zero-based Unicode scalar indices in the original display
text, even when the match used a generated phonetic key. `TEXT` is the
unmodified candidate. TEXT is last so the first four fields are tab-free and a
consumer can split on the first four tabs even when TEXT itself contains tabs.

```sh
printf 'apple\nbanana\n' | pixi run yuragi --filter ba --explain
1	390	original	0,1	banana
```

Use `--limit N` to emit at most the best N candidates. A non-empty query that
matches nothing exits with status 1 and writes no candidate output.

## Language modes

Language selection is explicit and small:

| Mode | Search keys | Example |
| --- | --- | --- |
| `auto` | Original/direct text only | `--lang auto --filter 京` |
| `zh` | Direct text plus bounded pinyin keys | `--lang zh --filter bjdx` |
| `ja` | Direct text plus bounded kana/romaji keys | `--lang ja --filter kamera` |
| `ko` | Direct text plus bounded Hangul romanized, initial, and keyboard keys | `--lang ko --filter hangeul` |

```sh
printf '北京大学\n上海\n' | yuragi --lang zh --filter bjdx
# 北京大学

printf 'カメラ\n東京\n' | yuragi --lang ja --filter kamera
# カメラ

printf '한글\n서울\n' | yuragi --lang ko --filter hangeul
# 한글
```

Japanese kana and romaji are built in through Yomi. General Kanji readings are
not guessed: they require a separately licensed dictionary/provider, which is
not bundled in `0.1.0`. For example, `日本語` is still searchable directly, but
`nihongo` is not promised without such a provider. `auto` remains direct-only
for the same reason—it is a deterministic default, not partial language
detection.

Use `--read0` and `--print0` for NUL framing when filenames can contain
newlines. Smart case is the default; `--ignore-case` and `--no-ignore-case`
provide hard ASCII case-sensitivity overrides.

## Interactive

Omit `--filter` to open a fixed-height picker inline on the controlling terminal:

```sh
ls | yuragi
```

In a development checkout, use `ls | pixi run yuragi` instead; this rebuilds
the binary before running it.

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
| Enter | Accept marks, or the cursor candidate; with no match, stay open |
| Esc, Ctrl-C | Abort |
| Down, Ctrl-N | Move to the next candidate |
| Up, Ctrl-P | Move to the previous candidate |
| TAB | With `--multi`, toggle the cursor mark and move down |
| Shift-TAB | With `--multi`, toggle the cursor mark and move up |
| Left/Right, Ctrl-B/Ctrl-F | Move the query cursor by grapheme |
| Home/End, Ctrl-A/Ctrl-E | Move to the start/end of the query |
| Backspace, Ctrl-H | Delete the previous grapheme or selection |
| Delete, Ctrl-D | Delete the next grapheme or selection |
| Ctrl-K | Delete from the cursor to the end of the query |
| Ctrl-U | Clear the query |
| Ctrl-W | Delete the previous Unicode word |
| Ctrl-Z/Ctrl-Y | Undo/redo a query edit |
| Bracketed paste | Insert the complete paste as one undoable transaction |

Marks follow candidate source identities, so they survive query refinement
even while a marked candidate is absent from the current matches. TAB and
Shift-TAB are inert without `--multi`.

For terminal safety, the interactive list displays C0 controls and DEL as
visible Unicode control pictures. This substitution affects display cells
only: Yuragi retains the original candidate record and emits its original valid
UTF-8 bytes and requested record framing when selected. Invalid UTF-8 retains
the documented lossy-decoding behavior.

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
- `PLAN.md`: product boundaries, release gates, and acceptance evidence

See [the architecture](docs/architecture.md), [design principles](docs/design.md),
and [roadmap](docs/roadmap.md) before proposing a new dependency or feature.

## License

Licensed under either Apache-2.0 or MIT, at your option.
