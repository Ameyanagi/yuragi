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
