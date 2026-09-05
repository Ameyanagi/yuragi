# Benchmarks

For cross-project claims, run the versioned fair protocol:

```sh
pixi run bench-fair
```

It uses the same deterministic corpus, queries, and result limit as Yuru and
reports p50/p95 for forced full scans, repeated queries, and incremental query
extensions. See [fair-search-protocol.md](fair-search-protocol.md) for the exact
specification, current same-machine results, threading caveats, and why a
portable memory ratio is not yet reported.

Prepared language-mode release measurements follow
[`cjk-search-v1`](cjk-search-protocol.md): deterministic 10k/100k corpora,
three warmups, 31 measured samples, p50/p95, exact semantic checksums, and
separate preparation/search counters. Record profiles outside the timed
samples. The protocol also explains why SIMD is not currently justified for
the branch-heavy fuzzy loop.

Profile large empty-query picker construction separately with:

```sh
pixi run mojo build --Werror -O3 -g1 -I src \
  benchmarks/bench_interactive_state.mojo \
  -o /tmp/yuragi-interactive-state
YURAGI_PROFILE=1 /tmp/yuragi-interactive-state &
yuragi_profile_pid=$!
trap 'kill "$yuragi_profile_pid" 2>/dev/null || true' EXIT INT TERM
sample "$yuragi_profile_pid" 5 \
  -file /tmp/yuragi-interactive-state.sample.txt
wait "$yuragi_profile_pid"
trap - EXIT INT TERM
test -s /tmp/yuragi-interactive-state.sample.txt
```

On the Apple M4/macOS 26.5/Mojo 1.0.0 profiling run, the former 100,000-row
eager model build measured 2.120/2.279 ms p50/p95 and the application deep copy
0.701/0.824 ms. Lazy identity rows reduced model build to 0/1 µs at the
benchmark timer's resolution and reduced the 100,000-candidate application copy
to 0.180/0.191 ms in the adjacent run. The checksum and exact total keep the
lazy path observable.
Treat sub-microsecond readings as "below useful timer resolution," not as an
exact zero-cost claim.
The long-running sampling mode captured 4,191 active main-thread samples;
1,496 (35.7%) were in `_FinderApplication.__init__` and 695 (16.6%) in the
owned optional-model teardown. These are historical pre-move measurements. The
current session swaps its live model with an empty placeholder and moves the
live model into the host, so no `FinderModel`, `SearchIndex`, or corpus copy
remains at that boundary. Rerun the benchmark before making a current startup
latency claim.

The older orchestration microbenchmark remains available:

Run the deterministic in-process search benchmark with:

```sh
pixi run bench-search
```

`bench_search.mojo` measures Yuragi's complete bounded interactive ranking path
after candidate ingestion: matcher construction, scoring, pre-limit match
counting, top-K retention, and retained-row materialization. It is a diagnostic
microbenchmark, not release evidence unless it performs the three warmups and
31-sample p50/p95 procedure above. The checksum and exact total match count
prevent dead-code elimination and semantic benchmark drift.

This is orchestration evidence, not a cross-machine marketing claim. Record the
CPU, OS, `Mojo 1.0.0`, and commit when comparing results. Run release-mode
compiled executable benchmarks separately for full stdin/process costs.

The language parity matrix separates UTF-8 ingestion, Yomi representation
generation by language, Hibana prepared-candidate scoring, source projection,
and complete process time. Publish language-mode numbers only for deterministic
synthetic data or licensed/provenanced corpora.

## Input and interactive scaling

[Interactive responsiveness protocol](interactive-responsiveness.md) records the
fixed 100k CJK terminal latency test and before/after 1k/10k/50k marked-selection
measurements. Commands, corpus construction, hardware, optimization settings,
and [raw samples](results/interactive-2026-09-05.json) are included.
