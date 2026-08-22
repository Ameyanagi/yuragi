# Releasing

1. Run `pixi run --locked check` on a clean tree.
2. Update the changelog, compatibility notes, and package version.
3. Tag the exact tested commit as `vX.Y.Z`.
4. Replace the local `source.path` in the modular-community recipe submission
   with the repository URL and full 40-character tag commit SHA.
5. Reset the Conda build number to zero for a new version; increment it only
   when rebuilding the same source version.
6. Build the recipe and verify its installed-package smoke test.
7. Publish benchmark results only with the checked-in methodology.

For the prepared/CJK search release, publish new immutable Hibana and Yomi
versions first on `osx-arm64`, `linux-64`, and `linux-aarch64`. Never overwrite
the hosted Hibana `0.0.0` filename with different contents. Pin the new
`mojo-hibana` and `mojo-yomi` versions in both Pixi and the Yuragi recipe,
regenerate the three-platform lock, and add installed-package CJK/prepared-search
CLI smoke coverage before tagging Yuragi.

The tag workflow creates a source archive after the supported CI matrix passes.
Publishing to modular-community is a separate reviewed operation.
