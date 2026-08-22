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
- Non-empty queries use Hibana's deterministic direct-text scorer and bounded
  top-K retention. Explicit phonetic language modes remain gated on Yomi.
- Interactive mode is implemented as an inline MojoTUI picker on the controlling
  terminal, with identity-stable selection, query seeding, automation, and
  multi-select. Search is still synchronous and input is indexed before opening.
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
- `2`: invalid command-line usage, decoding/I/O failure, unavailable mode, or
  unexpected internal/operational failure;
- `130`: interactive abort through Escape or Ctrl-C.
