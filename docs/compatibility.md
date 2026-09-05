# Compatibility

## Toolchain

Release `0.1.0` pins Mojo `1.0.0`, Hibana `0.1.0`, Moji `0.1.0`, MojoTUI
`0.1.1`, and Yomi `0.1.1` exactly in both the Pixi workspace and package
metadata. Compiler or ecosystem upgrades are explicit compatibility events and
require the full locked test suite plus installed CLI verification on every
supported platform.

The current native executable links Mojo's shared compiler runtime. The Conda
package therefore carries a compiler-compatible `mojo-compiler` runtime
dependency until Mojo provides a smaller redistributable runtime package or a
supported fully static application build.

## Platforms

| Platform | Status |
| --- | --- |
| macOS ARM64 | CI target |
| Linux x86-64 | CI target |
| Linux ARM64 | CI target |
| Windows/WSL | Not yet supported or tested |
| GPU | Not supported unless explicitly listed in the roadmap |

The repository is experimental and has no source-compatibility promise before
1.0. Each release names the exact compiler and dependency versions used to
build it.

## Current CLI limitations

- Standard input is framed incrementally with explicit byte, record-count, and
  record-length budgets. Each invalid UTF-8 byte becomes U+FFFD REPLACEMENT
  CHARACTER. Completed candidates remain in memory and are indexed after EOF.
- `--filter ''` is implemented as identity selection.
- Non-empty queries use Hibana's deterministic scorer and bounded top-K
  retention over prepared direct and, when explicitly requested, phonetic keys.
- `--lang auto` is direct-text only. `--lang ja`, `zh`, and `ko` opt into
  language-specific Yomi keys. There is no mixed-script language detector.
- Japanese kana/romaji search is supported. General Kanji readings require an
  external licensed dictionary/provider and are not included in `0.1.0`.
- Interactive mode is implemented as an inline MojoTUI picker on the controlling
  terminal, with identity-stable selection, query seeding, automation, and
  multi-select. Search, final ordering, and highlighting run cooperatively
  between terminal events; input is indexed before opening. One candidate
  match is indivisible, so the time budget is cooperative rather than a hard
  wall-clock deadline.
- The picker uses a fixed keymap and does not yet support `--bind`.
- Preview, Windows line-oriented console behavior, and built-in filesystem
  walking are not yet implemented. Validated flat configuration settings and
  generated Bash, Zsh, Fish, and PowerShell bindings are available.

## CLI precedence

Yuragi parses and validates the complete argument list before selecting an
informational mode. Invalid or unknown options therefore exit with status 2
even when `--help` or `--version` is present. When both informational flags are
validly supplied, `--help` wins over `--version`, independent of flag order.

## Exit status

- `0`: successful output or an informational mode;
- `1`: no noninteractive match or nothing to accept;
- `2`: invalid command-line usage, standard-input I/O failure, unavailable mode, or
  unexpected internal/operational failure;
- `130`: interactive abort through Escape or Ctrl-C.

## Settings compatibility

The configuration file supports only the documented flat TOML schema for `lang`,
`case`, and `limit`. CLI values override corresponding environment values, which
override file values and defaults. Malformed or unsupported syntax is rejected
with path/key/value/correction context; use `--no-config` to bypass the file.
This parser does not claim general TOML compatibility. See
[configuration](configuration.md) for syntax, allowed values, and diagnostics.
