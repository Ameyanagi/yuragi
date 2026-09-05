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

## Pull-request source-archive smoke

Every PR and `main` push exercises the same `scripts/source-artifact.sh`
creation/checksum/restoration implementation used by release source and package
jobs. `scripts/test-source-artifact.py` verifies canonical contents, rejects a
corrupt archive before extraction, protects an existing destination, and requires
the upload/download/Pixi action pins in both workflows to match.

The smoke jobs upload one archive, download it on all three supported native
runners, verify/extract it into a fresh directory, install its locked Pixi
environment, and run `pixi run --locked build` there. The compiled CLI then runs
from a separate temporary working directory: direct filtering, NUL-framed
round-trip, and no-match exit status are checked. An empty explicit config makes
the check independent of user settings. The source archive cannot depend on a
checkout's `.git` or an existing build directory. The PR workflow has only
`contents: read` and contains no publishing job.

Local handoff checks:

```sh
python3 scripts/test-source-artifact.py
bash scripts/source-artifact.sh create HEAD yuragi-smoke /tmp/yuragi-archives
bash scripts/source-artifact.sh restore yuragi-smoke /tmp/yuragi-archives /tmp/yuragi-source
cd /tmp/yuragi-source
pixi run --locked build
pixi run --locked bash scripts/check-source-artifact.sh
```

Choose fresh temporary paths; restore refuses an existing destination.
