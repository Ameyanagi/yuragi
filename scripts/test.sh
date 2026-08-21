#!/usr/bin/env bash
set -euo pipefail

for test_file in tests/test_*.mojo; do
  mojo run --Werror -I src "$test_file"
done

mkdir -p .pixi/test-bin
mojo build --Werror -I src examples/basic.mojo -o .pixi/test-bin/basic
