#!/usr/bin/env bash
# Run in the extracted source after `pixi run --locked build`, within Pixi.
set -euo pipefail
source_root="$PWD"
test ! -e .git
test -s src/yuragi/main.mojo
test -x .pixi/bin/yuragi
artifact_fixture="$(mktemp -d "${TMPDIR:-/tmp}/yuragi-source-smoke.XXXXXX")"
trap 'rm -rf -- "$artifact_fixture"' EXIT
# The fresh working directory rules out accidental relative source dependencies.
# An explicit empty config keeps the consumer independent of a developer's setup.
cd "$artifact_fixture"
touch config.toml
export YURAGI_CONFIG_FILE="${artifact_fixture}/config.toml"
unset YURAGI_LANG YURAGI_CASE YURAGI_LIMIT
executable="${source_root}/.pixi/bin/yuragi"
printf 'apple\nbanana\n' > input
printf 'banana\n' > expected
"$executable" --filter ba < input > actual
cmp expected actual
printf 'line\nbreak\0plain\0' > framed
"$executable" --read0 --print0 --filter '' < framed > actual
cmp framed actual
status=0
"$executable" --filter zzzzz < input > actual || status=$?
[[ "$status" -eq 1 && ! -s actual ]] || {
  echo "extracted CLI must return 1 with empty output when no candidate matches" >&2
  exit 1
}
echo 'extracted source CLI passed (filter, NUL framing, no-match exit status)'
