# Releasing

Yuragi uses an immutable source tag plus the shared
[`Ameyanagi/mojo-channel`](https://github.com/Ameyanagi/mojo-channel).
Conda-forge supplies transitive infrastructure; publishing Yuragi itself there
is optional and is not part of this release path.

1. Update the workspace, recipe, lockfile, changelog, compatibility notes, and
   security policy. Regenerate `pixi.lock` through Pixi; never edit it manually.
2. Run `bash scripts/check-release.sh --metadata-only vX.Y.Z`,
   `pixi run --locked check`, `pixi run --locked package`, and
   `bash scripts/check-package.sh yuragi X.Y.Z SUBDIR` from a clean release
   candidate.
3. Confirm the installed package's version, direct, Japanese, Chinese, and
   Korean smoke tests pass. Confirm documentation still says that `auto` is
   direct-only and that general Japanese Kanji readings need a provider.
4. Merge only after all three native source and package CI targets pass.
5. Create an annotated `vX.Y.Z` tag at the tested `main` commit. The tag
   workflow checks its peeled target, `origin/main` ancestry, exact dependency
   metadata, and dated changelog.
6. The workflow builds one canonical source archive, writes its SHA-256 file,
   verifies that checksum before every extraction, and gates the source release
   on all source and installed-package jobs.
7. After the source release succeeds, dispatch the central channel workflow
   for repository `yuragi`, that immutable tag, and `publish=true`. Verify clean
   installs from `osx-arm64`, `linux-64`, and `linux-aarch64`.

Never move a published tag or overwrite a channel artifact. A correction uses
a new patch version.
