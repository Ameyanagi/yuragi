#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

printf 'first\r\n\nlast\r' >"$test_dir/input"
printf 'first\n\nlast\r\n' >"$test_dir/expected"
.pixi/bin/yuragi --filter '' \
  <"$test_dir/input" >"$test_dir/actual" 2>"$test_dir/stderr"
if ! cmp -s "$test_dir/expected" "$test_dir/actual"; then
  echo "empty-query CLI output changed ordering or record delimiters" >&2
  exit 1
fi

# Place the first byte of a three-byte UTF-8 scalar at the nominal 4 KiB
# buffer boundary for compiled CLI coverage. The unit test forces the exact
# chunk split; this fixture does not assume that OS reads fill the buffer.
printf -v padding '%*s' 4095 ''
padding="${padding// /a}"
printf '%s界\r\nsecond\n' "$padding" >"$test_dir/chunk-input"
printf '%s界\nsecond\n' "$padding" >"$test_dir/chunk-expected"
.pixi/bin/yuragi --filter '' \
  <"$test_dir/chunk-input" >"$test_dir/chunk-actual" \
  2>"$test_dir/chunk-stderr"
if ! cmp -s "$test_dir/chunk-expected" "$test_dir/chunk-actual"; then
  echo "boundary-layout stdin corrupted UTF-8 or subsequent records" >&2
  exit 1
fi

if ! .pixi/bin/yuragi --help | grep -Fxq \
  'Usage: yuragi --filter QUERY [--limit N] [--lang auto|zh|ja|ko]'; then
  echo "CLI help is missing the usage contract" >&2
  exit 1
fi

help_text="$(.pixi/bin/yuragi --help)"
if ! grep -Fxq \
  '      --lang LANGUAGE  phonetic language hint (default: auto)' \
  <<<"$help_text"; then
  echo "--lang help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '      --limit N        emit at most N best-ranked candidates' \
  <<<"$help_text"; then
  echo "--limit help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  'Exit codes: 0 = success, 1 = no match, 2 = error.' \
  <<<"$help_text"; then
  echo "CLI help is missing the active no-match exit code" >&2
  exit 1
fi
if [[ "$(.pixi/bin/yuragi --version --help)" != "$help_text" ]] || \
  [[ "$(.pixi/bin/yuragi --help --version)" != "$help_text" ]]; then
  echo "--help must win over --version regardless of their order" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi --help --unknown \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]]; then
  echo "invalid options must win over --help and exit 2 (got $exit_code)" >&2
  exit 1
fi
if [[ -s "$test_dir/stdout" ]] || \
  ! grep -Fxq 'yuragi: unknown argument: --unknown' "$test_dir/stderr"; then
  echo "invalid-option precedence did not produce its exact diagnostic" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi --lang zh --lang=ko --help \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]] || \
  ! grep -Fxq 'yuragi: --lang may be specified only once' "$test_dir/stderr"; then
  echo "duplicate --lang must be rejected consistently before --help" >&2
  exit 1
fi

printf 'banana\nbar\n' >"$test_dir/ranked-expected"
printf 'apple\nbanana\nbar\n' | .pixi/bin/yuragi --filter ba \
  >"$test_dir/ranked-actual" 2>"$test_dir/ranked-stderr"
if ! cmp -s "$test_dir/ranked-expected" "$test_dir/ranked-actual"; then
  echo "ranked filtering produced unexpected candidates or ordering" >&2
  exit 1
fi

printf 'apple\nbanana\nbar\n' | .pixi/bin/yuragi --filter ba \
  >"$test_dir/ranked-first" 2>"$test_dir/ranked-first-stderr"
printf 'apple\nbanana\nbar\n' | .pixi/bin/yuragi --filter ba \
  >"$test_dir/ranked-second" 2>"$test_dir/ranked-second-stderr"
if ! cmp -s "$test_dir/ranked-first" "$test_dir/ranked-second"; then
  echo "ranked filtering is not deterministic" >&2
  exit 1
fi

printf 'banana\n' >"$test_dir/limited-expected"
printf 'apple\nbanana\nbar\n' | .pixi/bin/yuragi --filter ba --limit 1 \
  >"$test_dir/limited-actual" 2>"$test_dir/limited-stderr"
if ! cmp -s "$test_dir/limited-expected" "$test_dir/limited-actual"; then
  echo "--limit 1 did not retain the single best candidate" >&2
  exit 1
fi

: >"$test_dir/empty-expected"
.pixi/bin/yuragi --filter '' </dev/null \
  >"$test_dir/empty-actual" 2>"$test_dir/empty-stderr"
if ! cmp -s "$test_dir/empty-expected" "$test_dir/empty-actual"; then
  echo "empty input with an empty query produced output" >&2
  exit 1
fi

set +e
printf 'apple\n' | .pixi/bin/yuragi --filter zz \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 1 ]]; then
  echo "a non-empty query with no match must exit 1 (got $exit_code)" >&2
  exit 1
fi
if ! cmp -s "$test_dir/empty-expected" "$test_dir/stdout"; then
  echo "a no-match result wrote candidate output" >&2
  exit 1
fi

set +e
printf '北京大学\nnotes\n' | .pixi/bin/yuragi --lang zh --filter bjdx \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]]; then
  echo "unavailable phonetic matching must exit 2 (got $exit_code)" >&2
  exit 1
fi
if [[ -s "$test_dir/stdout" ]]; then
  echo "blocked phonetic filtering wrote candidate output" >&2
  exit 1
fi
if ! grep -Fxq \
  'yuragi: --lang zh phonetic matching awaits the Yomi integration; direct matching works without --lang' \
  "$test_dir/stderr"; then
  echo "blocked phonetic filtering did not explain the Yomi gate" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi --filter ba --limit 0 \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]]; then
  echo "--limit 0 must exit 2 (got $exit_code)" >&2
  exit 1
fi
if [[ -s "$test_dir/stdout" ]] || ! grep -Fxq \
  'yuragi: --limit requires a positive candidate count' \
  "$test_dir/stderr"; then
  echo "--limit 0 did not produce its exact diagnostic" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi </dev/null >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]]; then
  echo "invocation without --filter must exit 2 (got $exit_code)" >&2
  exit 1
fi
if ! grep -q 'interactive mode is not available' "$test_dir/stderr"; then
  echo "missing-filter invocation did not explain the unavailable mode" >&2
  exit 1
fi

set +e
printf '\xff\n' | .pixi/bin/yuragi --filter '' \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]]; then
  echo "invalid UTF-8 input must exit 2 (got $exit_code)" >&2
  exit 1
fi
if [[ -s "$test_dir/stdout" ]]; then
  echo "invalid UTF-8 input produced candidate output" >&2
  exit 1
fi
if ! grep -Fq 'yuragi: input error:' "$test_dir/stderr" || \
  ! grep -Fq 'invalid UTF-8' "$test_dir/stderr"; then
  echo "invalid UTF-8 input did not produce a useful diagnostic" >&2
  exit 1
fi

# Bash's `<&-` closes descriptor 0 for the child and forces `read_bytes()` to
# take the application's operational input-error path.
set +e
.pixi/bin/yuragi --filter '' <&- \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]]; then
  echo "stdin read failure must exit 2 (got $exit_code)" >&2
  exit 1
fi
if [[ -s "$test_dir/stdout" ]]; then
  echo "stdin read failure produced candidate output" >&2
  exit 1
fi
if ! grep -Fq 'yuragi: input error:' "$test_dir/stderr" || \
  ! grep -Fq 'read bytes' "$test_dir/stderr"; then
  echo "stdin read failure did not produce a useful diagnostic" >&2
  exit 1
fi
