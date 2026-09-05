# Interactive responsiveness protocol

Measured 2026-09-05 on Apple M4, macOS 26.5.1 ARM64, pinned Mojo 1.0.0.
Builds use `--Werror -O3` and the published dependency versions in `pixi.lock`.
Other ecosystem builds were active on the host; timings are observations, not
portable performance guarantees or a wall-clock scheduler promise.

## Reproduce

```sh
pixi run --locked mojo build --Werror -O3 -I src \
  src/yuragi/main.mojo -o .pixi/bin/yuragi-benchmark
python3 benchmarks/bench_pty_latency.py .pixi/bin/yuragi-benchmark
pixi run --locked mojo build --Werror -O3 -I src \
  benchmarks/bench_multiselect.mojo -o .pixi/bin/bench-marks
.pixi/bin/bench-marks
```

The PTY benchmark constructs exactly 100,000 records as
`北京 カメラ 카메라 検索 {i:06d}\n`, UTF-8 encoded, for `i=0..99999`.
The SHA-256 is
`711aa14ba7790eacaa30358f567e728b62d04162a12fae5846d55dc7ea25d96c`.
Each process starts with no query or result limit. After the initial frame, it
receives `京`, waits for a real query frame and the `Searching` indicator, then
receives Escape or Ctrl-C while ranking remains incomplete. The benchmark uses
the real terminal parser/backend and checks restoration of terminal attributes.
Key latency ends when the terminal screen decoder observes the new frame. Abort
latency ends at process exit and includes normal index destruction. The timeout
poll is 1 ms. Percentiles use nearest rank; stdout is JSON with every sample.

| Measurement | Samples | Median (ms) | p95 (ms) | Max (ms) |
| --- | ---: | ---: | ---: | ---: |
| Key to query/searching frame | 62 | 16.646 | 25.783 | 28.441 |
| Escape to process exit | 31 | 48.991 | 62.431 | 77.065 |
| Ctrl-C to process exit | 31 | 19.913 | 40.365 | 60.450 |

The UI processes at most 64 search units or 2 ms between terminal turns,
including final heap drain, exact highlight reconstruction, and reversal. Only
an active generation arms a public adapter deadline, and one outstanding turn
is scheduled at a time; an idle picker has no periodic search timer.
An exact candidate match is indivisible, so pathological candidate/query lengths
can exceed that cooperative time budget. `--max-record-bytes` bounds input
records; it is intentionally distinct from a deadline inside Hibana. No private
async runtime API or approximate ranking is used.

## Marking and acceptance scaling

`bench_multiselect.mojo` builds 100,000 records with distinct source IDs and
`北京 カメラ 카메라 {i}` text. It marks even IDs in reverse source order, then
accepts the complete selection. It prints five independent measurements each
for 1,000, 10,000, and 50,000 marks. Medians below include candidate-copy ownership
in acceptance and exclude corpus/index construction. All outputs are checked
for the expected count; behavioral tests separately verify each emitted ID.

The baseline is `c22d3bae5b3ab01e7acb12a53de4dcb710637e36`. To reproduce the
baseline, extract that commit outside `src` and build the same benchmark with
`-I /path/to/baseline/src`; its exercised marking/selection functions are shared
by both revisions. Both paths use the same optimization level and corpus.

| Marks | Old marking (ms) | New marking (ms) | Old accept (ms) | New accept (ms) |
| ---: | ---: | ---: | ---: | ---: |
| 1,000 | 2.555 | 0.093 | 24.229 | 12.997 |
| 10,000 | 228.960 | 0.656 | 748.347 | 22.682 |
| 50,000 | 9,688.378 | 2.217 | 17,091.089 | 27.941 |

Hash membership makes marking expected O(M). Acceptance is one corpus-order
pass, O(N + M), preserving duplicate-text identities and source order. At a fixed
100k corpus, scanning dominates small selections; increasing marks by 50 times
increased median acceptance by roughly 2.2 times, replacing the old quadratic
sorting and repeated corpus searches.
