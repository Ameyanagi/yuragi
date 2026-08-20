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

- Standard input must be valid UTF-8 and is currently buffered in memory.
- `--filter ''` is implemented as identity selection.
- Non-empty queries exit with status 2 until Moji, Hibana, and Yomi pass the
  integration gates in `PLAN.md`.
- Interactive mode, Windows line-oriented console behavior, configuration, and
  shell bindings are not yet implemented.

## CLI precedence

Yuragi parses and validates the complete argument list before selecting an
informational mode. Invalid or unknown options therefore exit with status 2
even when `--help` or `--version` is present. When both informational flags are
validly supplied, `--help` wins over `--version`, independent of flag order.

## Exit status

- `0`: successful output or an informational mode;
- `2`: invalid command-line usage or a requested mode that is not implemented;
- `1`: input decoding, I/O, or unexpected internal/operational failure.
