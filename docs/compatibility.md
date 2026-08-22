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

- Standard input is buffered in memory and decoded lossily: each invalid UTF-8
  byte becomes U+FFFD REPLACEMENT CHARACTER, matching fzf behavior.
- `--filter ''` is implemented as identity selection.
- Non-empty queries use Hibana's deterministic scorer and bounded top-K
  retention over prepared direct and, when explicitly requested, phonetic keys.
- `--lang auto` is direct-text only. `--lang ja`, `zh`, and `ko` opt into
  language-specific Yomi keys. There is no mixed-script language detector.
- Japanese kana/romaji search is supported. General Kanji readings require an
  external licensed dictionary/provider and are not included in `0.1.0`.
- Interactive mode is implemented as an inline MojoTUI picker on the controlling
  terminal, with identity-stable selection, query seeding, automation, and
  multi-select. Search is still synchronous and input is indexed before opening.
- The picker uses a fixed keymap and does not yet support `--bind`.
- Preview, Windows line-oriented console behavior, configuration-file loading,
  and built-in filesystem walking are not yet implemented. Read-only
  configuration-path resolution plus generated Bash, Zsh, Fish, and PowerShell
  bindings are available.

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
