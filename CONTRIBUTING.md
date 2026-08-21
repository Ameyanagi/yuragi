# Contributing

Thanks for helping build Yuragi.

## Development setup

1. Install Pixi.
2. Run `pixi install --locked`.
3. Run `pixi run check` before opening a pull request.

`pixi run check` formats, runs all TestSuite files, builds the executable with
warnings as errors, and exercises stdin/stdout/error behavior through the
compiled process. Use `pixi run package` when changing the recipe, executable
linkage, or installed CLI contract.

Use `pixi run format` to format Mojo sources. Do not edit `pixi.lock` directly;
update dependencies through Pixi and commit the resulting lock change.

## Changes

- Keep pull requests focused on one behavior or architectural decision.
- Add focused tests before fixing behavioral bugs.
- Treat compiler warnings as defects.
- Do not add runtime dependencies in Python, Rust, C, or C++ without an accepted
  design discussion.
- Keep generated files deterministic and record source version, checksum,
  license, generator command, and update procedure.
- Update the changelog and compatibility notes for user-visible changes.
- Benchmark performance work with checked-in methodology; do not add unsupported
  superiority claims.
- Read `PLAN.md` before adding Moji, Hibana, Yomi, or MojoTUI. A dependency is
  accepted only after its documented integration gate has evidence and an
  installable version; sibling-source imports are not a release strategy.

## Public contracts

Command-line flags, stdin/stdout behavior, exit codes, configuration, and shell
integration are compatibility commitments. Keep internal modules private until
a separately reusable contract is documented and tested.
