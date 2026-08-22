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

printf 'a\nb\0c\0' >"$test_dir/nul-round-trip-input"
printf 'a\nb\0c\0' >"$test_dir/nul-round-trip-expected"
.pixi/bin/yuragi --read0 --print0 --filter '' \
  <"$test_dir/nul-round-trip-input" >"$test_dir/nul-round-trip-actual" \
  2>"$test_dir/nul-round-trip-stderr"
if ! cmp -s \
  "$test_dir/nul-round-trip-expected" "$test_dir/nul-round-trip-actual"; then
  echo "NUL framing did not preserve a newline inside a candidate" >&2
  exit 1
fi

printf 'banana\0' >"$test_dir/print0-expected"
printf 'apple\nbanana\n' | .pixi/bin/yuragi --filter ba --print0 \
  >"$test_dir/print0-actual" 2>"$test_dir/print0-stderr"
if ! cmp -s "$test_dir/print0-expected" "$test_dir/print0-actual"; then
  echo "--print0 did not NUL-terminate ranked output" >&2
  exit 1
fi

printf 'banana\n' >"$test_dir/read0-expected"
printf 'banana\0apple\0' | .pixi/bin/yuragi --read0 --filter ba \
  >"$test_dir/read0-actual" 2>"$test_dir/read0-stderr"
if ! cmp -s "$test_dir/read0-expected" "$test_dir/read0-actual"; then
  echo "--read0 did not parse NUL-delimited input independently of output" >&2
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
  'Usage: yuragi [--filter QUERY | --query QUERY] [--limit N]'; then
  echo "CLI help is missing the usage contract" >&2
  exit 1
fi

help_text="$(.pixi/bin/yuragi --help)"
if ! grep -Fxq \
  '  -q, --query STR       seed the interactive prompt with STR' \
  <<<"$help_text"; then
  echo "--query help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '  -1, --select-1        accept a sole initial match without the picker' \
  <<<"$help_text"; then
  echo "--select-1 help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '  -0, --exit-0          exit 1 on no initial matches without the picker' \
  <<<"$help_text"; then
  echo "--exit-0 help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '  -m, --multi           select multiple candidates with TAB/Shift-TAB' \
  <<<"$help_text"; then
  echo "--multi help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '      --lang LANGUAGE   phonetic language hint (default: auto)' \
  <<<"$help_text"; then
  echo "--lang help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '      --limit N         emit at most N best-ranked candidates' \
  <<<"$help_text"; then
  echo "--limit help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '  -i, --ignore-case     match case-insensitively (ASCII)' \
  <<<"$help_text"; then
  echo "--ignore-case help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '  +i, --no-ignore-case  match case-sensitively' \
  <<<"$help_text"; then
  echo "--no-ignore-case help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '      --read0           read NUL-delimited candidates from standard input' \
  <<<"$help_text"; then
  echo "--read0 help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '      --print0          write NUL-delimited candidates to standard output' \
  <<<"$help_text"; then
  echo "--print0 help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  '      --explain         print rank, score, key kind, and match positions' \
  <<<"$help_text"; then
  echo "--explain help description is not column-aligned" >&2
  exit 1
fi
if ! grep -Fxq \
  'Exit codes: 0 = success, 1 = no match, 2 = error, 130 = interactive abort.' \
  <<<"$help_text"; then
  echo "CLI help is missing the documented exit-code contract" >&2
  exit 1
fi

# POSIX cksum plus byte length pins each generated integration script exactly,
# while syntax checks catch errors that a stable but invalid fixture would miss.
shell_names=(bash zsh fish powershell)
shell_checksums=(
  '2958611478 2535'
  '1613825818 2465'
  '4250646206 2398'
  '874700008 3520'
)
for index in "${!shell_names[@]}"; do
  shell_name="${shell_names[$index]}"
  .pixi/bin/yuragi shell "$shell_name" \
    >"$test_dir/$shell_name-script" 2>"$test_dir/$shell_name-stderr"
  actual_checksum="$(cksum "$test_dir/$shell_name-script" | awk '{print $1 " " $2}')"
  if [[ "$actual_checksum" != "${shell_checksums[$index]}" ]] || \
    [[ -s "$test_dir/$shell_name-stderr" ]]; then
    echo "$shell_name integration changed from its byte-exact fixture" >&2
    exit 1
  fi
done
bash -n "$test_dir/bash-script"
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$test_dir/zsh-script"
fi

config_path="$(
  YURAGI_CONFIG_FILE=/explicit/yuragi.toml \
  XDG_CONFIG_HOME=/ignored-xdg HOME=/ignored-home \
  .pixi/bin/yuragi config path
)"
if [[ "$config_path" != /explicit/yuragi.toml ]]; then
  echo 'YURAGI_CONFIG_FILE must win config path precedence' >&2
  exit 1
fi
config_path="$(
  env -u YURAGI_CONFIG_FILE XDG_CONFIG_HOME=/xdg HOME=/ignored-home \
    .pixi/bin/yuragi config path
)"
if [[ "$config_path" != /xdg/yuragi/config.toml ]]; then
  echo 'XDG_CONFIG_HOME must win HOME config path precedence' >&2
  exit 1
fi
config_path="$(
  env -u YURAGI_CONFIG_FILE -u XDG_CONFIG_HOME HOME=/home/person \
    .pixi/bin/yuragi config path
)"
if [[ "$config_path" != /home/person/.config/yuragi/config.toml ]]; then
  echo 'HOME config path fallback changed' >&2
  exit 1
fi

set +e
env -u YURAGI_CONFIG_FILE -u XDG_CONFIG_HOME -u HOME \
  .pixi/bin/yuragi config path \
  >"$test_dir/config-path-stdout" 2>"$test_dir/config-path-stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]] || [[ -s "$test_dir/config-path-stdout" ]] || \
  ! grep -Fxq \
    'yuragi: config error: configuration path requires YURAGI_CONFIG_FILE, XDG_CONFIG_HOME, or HOME; set one of those environment variables' \
    "$test_dir/config-path-stderr"; then
  echo 'unresolved config path must be an operational exit-2 error' >&2
  exit 1
fi

doctor_config_home="$test_dir/doctor-config"
set +e
env -u YURAGI_CONFIG_FILE -u SHELL \
  XDG_CONFIG_HOME="$doctor_config_home" HOME=/ignored PATH='' \
  .pixi/bin/yuragi doctor \
  >"$test_dir/doctor-stdout" 2>"$test_dir/doctor-stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 0 ]] || [[ -s "$test_dir/doctor-stderr" ]]; then
  echo 'doctor warnings must remain a successful read-only diagnostic' >&2
  exit 1
fi
printf '%s\n' \
  'Yuragi doctor' \
  'ok version: 0.0.0' \
  'ok executable: running' \
  "info config path: $doctor_config_home/yuragi/config.toml" \
  'info config file: absent; loading is not enabled in this release' \
  'warn shell hint: SHELL is not set' \
  'warn path finder: fd, fdfind, and find were not found on PATH' \
  'info shell scripts: dependencies are checked when each binding runs' \
  >"$test_dir/doctor-expected"
if ! cmp -s "$test_dir/doctor-expected" "$test_dir/doctor-stdout"; then
  echo 'doctor warning report changed from its exact fixture' >&2
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
  ! grep -Fxq \
    "yuragi: unknown argument '--unknown' (try 'yuragi --help')" \
    "$test_dir/stderr"; then
  echo "invalid-option precedence did not produce its exact diagnostic" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi --lang zh --lang=ko --help \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 0 ]] || [[ -s "$test_dir/stderr" ]] || \
  [[ "$(<"$test_dir/stdout")" != "$help_text" ]]; then
  echo "last-wins --lang parsing must allow --help to win" >&2
  exit 1
fi

printf 'read\n' >"$test_dir/last-case-wins-expected"
printf 'READ\nread\n' | \
  .pixi/bin/yuragi --filter re --ignore-case --no-ignore-case \
  >"$test_dir/last-case-wins-actual" 2>"$test_dir/last-case-wins-stderr"
if ! cmp -s \
  "$test_dir/last-case-wins-expected" "$test_dir/last-case-wins-actual" || \
  [[ -s "$test_dir/last-case-wins-stderr" ]]; then
  echo "the last case-sensitivity flag did not win" >&2
  exit 1
fi

printf 'banana\n' >"$test_dir/select-1-expected"
printf 'banana\n' | .pixi/bin/yuragi --select-1 --multi \
  >"$test_dir/select-1-actual" 2>"$test_dir/select-1-stderr"
if ! cmp -s "$test_dir/select-1-expected" "$test_dir/select-1-actual" || \
  [[ -s "$test_dir/select-1-stderr" ]]; then
  echo "--select-1 --multi did not accept a sole initial match without a TTY" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi --exit-0 </dev/null \
  >"$test_dir/exit-0-stdout" 2>"$test_dir/exit-0-stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 1 ]] || [[ -s "$test_dir/exit-0-stdout" ]] || \
  [[ -s "$test_dir/exit-0-stderr" ]]; then
  echo "--exit-0 with no initial match must exit 1 with empty output" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi --query x --filter y \
  >"$test_dir/query-filter-stdout" 2>"$test_dir/query-filter-stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]] || [[ -s "$test_dir/query-filter-stdout" ]] || \
  ! grep -Fxq \
    'yuragi: --query cannot be used with --filter' \
    "$test_dir/query-filter-stderr"; then
  echo "--query with --filter must produce its exact usage error" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi --multi --filter x \
  >"$test_dir/multi-filter-stdout" 2>"$test_dir/multi-filter-stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]] || [[ -s "$test_dir/multi-filter-stdout" ]] || \
  ! grep -Fxq \
    'yuragi: --multi cannot be used with --filter' \
    "$test_dir/multi-filter-stderr"; then
  echo "--multi with --filter must produce its exact usage error" >&2
  exit 1
fi

printf 'banana\nbar\n' >"$test_dir/ranked-expected"
printf 'apple\nbanana\nbar\n' | .pixi/bin/yuragi --filter ba \
  >"$test_dir/ranked-actual" 2>"$test_dir/ranked-stderr"
if ! cmp -s "$test_dir/ranked-expected" "$test_dir/ranked-actual"; then
  echo "ranked filtering produced unexpected candidates or ordering" >&2
  exit 1
fi

printf 'banana\n' >"$test_dir/attached-filter-expected"
printf 'apple\nbanana\n' | .pixi/bin/yuragi -fba \
  >"$test_dir/attached-filter-actual" 2>"$test_dir/attached-filter-stderr"
if ! cmp -s \
  "$test_dir/attached-filter-expected" "$test_dir/attached-filter-actual"; then
  echo "attached -f query did not select banana" >&2
  exit 1
fi

# This byte-exact fixture pins Hibana's published scoring table.
printf '1	390	original	0,1	banana\n' >"$test_dir/explain-expected"
printf 'apple\nbanana\n' | .pixi/bin/yuragi --filter ba --explain \
  >"$test_dir/explain-actual" 2>"$test_dir/explain-stderr"
if ! cmp -s "$test_dir/explain-expected" "$test_dir/explain-actual"; then
  echo "--explain did not render the ranked Hibana match report" >&2
  exit 1
fi

printf '1	265	original	0	北京大学\n' >"$test_dir/explain-cjk-expected"
printf '北京大学\n' | .pixi/bin/yuragi --filter 北 --explain \
  >"$test_dir/explain-cjk-actual" 2>"$test_dir/explain-cjk-stderr"
if ! cmp -s "$test_dir/explain-cjk-expected" \
  "$test_dir/explain-cjk-actual"; then
  echo "--explain positions are not Unicode scalar indices" >&2
  exit 1
fi

set +e
printf 'apple\n' | .pixi/bin/yuragi --filter zz --explain \
  >"$test_dir/explain-no-match-stdout" \
  2>"$test_dir/explain-no-match-stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 1 ]] || [[ -s "$test_dir/explain-no-match-stdout" ]]; then
  echo "--explain with no matches must exit 1 with empty stdout" >&2
  exit 1
fi

printf '%s\n' \
  'yuragi: --explain writes a line-oriented report and conflicts with --print0' \
  >"$test_dir/explain-print0-expected-stderr"
set +e
.pixi/bin/yuragi --filter ba --explain --print0 </dev/null \
  >"$test_dir/explain-print0-stdout" \
  2>"$test_dir/explain-print0-stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]] || [[ -s "$test_dir/explain-print0-stdout" ]] || \
  ! cmp -s "$test_dir/explain-print0-expected-stderr" \
    "$test_dir/explain-print0-stderr"; then
  echo "--explain with --print0 must produce its exact diagnostic" >&2
  exit 1
fi

printf '%s\n' \
  'yuragi: --explain requires a non-empty --filter query; an empty query performs no matching' \
  >"$test_dir/explain-empty-expected-stderr"
set +e
.pixi/bin/yuragi --filter '' --explain </dev/null \
  >"$test_dir/explain-empty-stdout" 2>"$test_dir/explain-empty-stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]] || [[ -s "$test_dir/explain-empty-stdout" ]] || \
  ! cmp -s "$test_dir/explain-empty-expected-stderr" \
    "$test_dir/explain-empty-stderr"; then
  echo "--explain with an empty query must produce its exact diagnostic" >&2
  exit 1
fi

printf 'READ\n' >"$test_dir/smart-case-expected"
printf 'READ\nread\n' | .pixi/bin/yuragi --filter RE \
  >"$test_dir/smart-case-actual" 2>"$test_dir/smart-case-stderr"
if ! cmp -s "$test_dir/smart-case-expected" "$test_dir/smart-case-actual"; then
  echo "smart case did not make an uppercase query case-sensitive" >&2
  exit 1
fi

printf 'READ\nread\n' >"$test_dir/ignore-case-expected"
printf 'READ\nread\n' | .pixi/bin/yuragi --filter RE --ignore-case \
  >"$test_dir/ignore-case-actual" 2>"$test_dir/ignore-case-stderr"
if ! cmp -s "$test_dir/ignore-case-expected" "$test_dir/ignore-case-actual"; then
  echo "--ignore-case did not apply ASCII-insensitive matching" >&2
  exit 1
fi

printf 'read\n' >"$test_dir/exact-case-expected"
printf 'READ\nread\n' | .pixi/bin/yuragi --filter re --no-ignore-case \
  >"$test_dir/exact-case-actual" 2>"$test_dir/exact-case-stderr"
if ! cmp -s "$test_dir/exact-case-expected" "$test_dir/exact-case-actual"; then
  echo "--no-ignore-case did not apply exact-case matching" >&2
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
.pixi/bin/yuragi --lang zh --filter '' </dev/null \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]] || [[ -s "$test_dir/stdout" ]] || \
  ! grep -Fxq \
    'yuragi: --lang zh phonetic matching awaits the Yomi integration; direct matching works without --lang' \
    "$test_dir/stderr"; then
  echo "empty-query phonetic filtering must explain the Yomi gate" >&2
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
  "yuragi: invalid value '0' for --limit: the candidate count must be at least 1" \
  "$test_dir/stderr"; then
  echo "--limit 0 did not produce its exact diagnostic" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi --explain </dev/null \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]] || [[ -s "$test_dir/stdout" ]] || \
  ! grep -Fxq \
    'yuragi: --explain is a filter-mode report and requires --filter QUERY' \
    "$test_dir/stderr"; then
  echo "interactive --explain must produce its exact diagnostic" >&2
  exit 1
fi

set +e
.pixi/bin/yuragi --lang zh </dev/null \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
exit_code=$?
set -e
if [[ $exit_code -ne 2 ]] || [[ -s "$test_dir/stdout" ]] || \
  ! grep -Fxq \
    'yuragi: --lang zh phonetic matching awaits the Yomi integration; direct matching works without --lang' \
    "$test_dir/stderr"; then
  echo "interactive phonetic mode must explain the Yomi gate" >&2
  exit 1
fi

printf 'caf\xef\xbf\xbd\napple\n' >"$test_dir/lossy-utf8-expected"
printf 'caf\xff\napple\n' | .pixi/bin/yuragi --filter '' \
  >"$test_dir/lossy-utf8-actual" 2>"$test_dir/lossy-utf8-stderr"
if ! cmp -s "$test_dir/lossy-utf8-expected" "$test_dir/lossy-utf8-actual" || \
  [[ -s "$test_dir/lossy-utf8-stderr" ]]; then
  echo "invalid UTF-8 bytes were not replaced with U+FFFD" >&2
  exit 1
fi

printf 'caf\xff\napple\n' | .pixi/bin/yuragi --filter a \
  >"$test_dir/lossy-filter-actual" 2>"$test_dir/lossy-filter-stderr"
if ! grep -Fxq 'apple' "$test_dir/lossy-filter-actual" || \
  [[ -s "$test_dir/lossy-filter-stderr" ]]; then
  echo "lossy UTF-8 input did not remain filterable" >&2
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
