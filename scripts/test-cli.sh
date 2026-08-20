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

if ! .pixi/bin/yuragi --help | grep -q '^Usage: yuragi --filter QUERY'; then
  echo "CLI help is missing the usage contract" >&2
  exit 1
fi

help_text="$(.pixi/bin/yuragi --help)"
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

set +e
printf '北京大学\nnotes\n' | .pixi/bin/yuragi --lang zh --filter bjdx \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]]; then
  echo "unavailable matching must exit 2 (got $exit_code)" >&2
  exit 1
fi
if [[ -s "$test_dir/stdout" ]]; then
  echo "blocked filtering wrote candidate output" >&2
  exit 1
fi
if ! grep -Fxq \
  'yuragi: non-empty --filter requires the pending Moji/Hibana/Yomi integration' \
  "$test_dir/stderr"; then
  echo "blocked filtering did not explain its integration gate" >&2
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
if [[ $exit_code -ne 1 ]]; then
  echo "invalid UTF-8 input must exit 1 (got $exit_code)" >&2
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
if [[ $exit_code -ne 1 ]]; then
  echo "stdin read failure must exit 1 (got $exit_code)" >&2
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
