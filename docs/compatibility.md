# Compatibility

## Toolchain

Development currently pins Mojo `1.0.0`. The Pixi environment and Conda build
recipe pin the compiler used to build the Yuragi executable. Compiler upgrades
are explicit compatibility events and require the full locked test suite plus
CLI and platform verification.

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
its first release. Each release names the exact compiler used to build it.

## Current CLI limitations

- Standard input is buffered in memory and decoded lossily: each invalid UTF-8
  byte becomes U+FFFD REPLACEMENT CHARACTER, matching fzf behavior.
- `--filter ''` is implemented as identity selection.
- Non-empty `--filter` queries rank candidates through the installed Hibana
  package.
- An inline interactive picker is implemented with a fixed keymap. It does not
  yet support `--bind`, configuration, or shell bindings.
- Phonetic `--lang` matching still awaits Yomi.

## CLI precedence

Yuragi parses and validates the complete argument list before selecting an
informational mode. Invalid or unknown options therefore exit with status 2
even when `--help` or `--version` is present. When both informational flags are
validly supplied, `--help` wins over `--version`, independent of flag order.

## Exit status

- `0`: success or an informational mode;
- `1`: no match or nothing accepted;
- `2`: usage or operational error, including standard-input I/O failures;
- `130`: interactive abort.
