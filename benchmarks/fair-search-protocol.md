# Fair Yuru/Yuragi plain-search protocol

`plain-search-v1` is the reproducible cross-project workload. Candidate `i` is
exactly:

```text
workspace/pkg-{i % 97}/src/component-{i}/view.mojo
```

| Candidates | Total UTF-8 bytes |
| ---: | ---: |
| 10,000 | 447,851 |
| 100,000 | 4,578,580 |

Both harnesses validate these totals, use case-insensitive fuzzy matching, and
retain 20 rows. The fixed cases are:

| Case | Query | Matches at 10k / 100k |
| --- | --- | ---: |
| all hit | `pkgsrcview` | 10,000 / 100,000 |
| no hit | `zzzzzzzz` | 0 / 0 |
| repeat base | `component1` | 3,439 / 40,951 |
| extension | `component1` -> `component100` | 37 / 856 remain |

Yuragi forces and measures full scans for every standalone query. It also times
the second, incremental operation after an untimed setup query. Its output
includes `scanned`, so a benchmark fails if the persistent `SearchIndex` stops
using the expected exact prior-match set. Yuru has no previous-query state; its
full `component1` and `component100` searches are the same-query comparators.

Run the optimized harnesses:

```sh
pixi run bench-fair

cd ../yuru
cargo bench --bench search fair_compare

# Separate Yuru's index/matcher advantage from its 100k parallel threshold.
RAYON_NUM_THREADS=1 cargo bench --bench search \
  'fair_compare/warm_search/.*/100000'
```

Yuru uses Criterion with 30 samples and reports robust intervals. Yuragi uses
three unreported warmups followed by 31 independent measured samples and prints
nearest-rank p50/p95, never only the fastest observation. Record hardware, OS,
compiler versions, thread settings, and commits with any published result.

## Reference run

Measured 2026-08-22 on an Apple M4 (10 physical cores), macOS 26.5.1, Rust
1.95.0, and Mojo 1.0.0. Values are milliseconds. Yuru shows its Criterion
central estimate; Yuragi shows p50/p95.

This is a historical pre-prepared-index result. Its exact source commit was not
recorded, so it must not be presented as `0.1.0` release or CJK evidence. A new
release comparison must record both exact commits and follow the current
3-warmup/31-sample protocol.

| Search | Size | Yuru default | Yuragi full | Yuragi indexed |
| --- | ---: | ---: | ---: | ---: |
| all hit | 10k | 1.901 | 28.618 / 30.029 | n/a |
| no hit | 10k | 0.344 | 25.532 / 29.724 | n/a |
| `component1` | 10k | 0.668 | 28.655 / 38.869 | 7.665 / 8.158 repeated |
| `component100` | 10k | 0.376 | 24.372 / 29.761 | 8.421 / 8.497 extension |
| all hit | 100k | 4.285 | 239.973 / 267.206 | n/a |
| no hit | 100k | 2.011 | 191.564 / 232.797 | n/a |
| `component1` | 100k | 2.348 | 233.579 / 353.268 | 96.974 / 105.336 repeated |
| `component100` | 100k | 1.335 | 248.809 / 317.769 | 112.463 / 268.791 extension |

Yuru's 100k default uses Rayon. Its one-thread central estimates were 17.161 ms
all-hit, 4.643 ms no-hit, 8.030 ms for `component1`, and 4.350 ms for
`component100`. The indexed Yuragi reductions should therefore be read first
against Yuragi's own full path: repeated `component1` is 2.41x faster at 100k,
and extending to `component100` is 2.21x faster than the same-query full scan.

Preparation is intentionally separate. Yuru's index-build central estimates
were 1.579 ms at 10k and 3.466 ms at 100k after an untimed corpus clone. Yuragi
candidate materialization p50/p95 was 0.899/0.963 ms and 8.376/8.891 ms;
the historical `SearchIndex` measured here only took ownership. The `0.1.0`
index instead prepares and owns its Hibana corpus plus a bounded key family for
each candidate. These rows measure different work and are not a valid speed
ratio for either the historical implementations or the current release.

## Limits

- Matching policy and ranking scores are not identical even though inputs,
  queries, case policy, and limits are fixed.
- Both scan their selected candidate set and retain top 20. Yuragi also computes
  exact pre-limit cardinality and match positions; Yuru does not expose total
  match cardinality through this API.
- Yuru is parallel at 100k by default. Current Yuragi large `AUTO` full searches
  use Hibana's exact coarse parallel shards; explicit CJK modes remain serial.
  The historical Yuragi values above predate that parallel path.
- No portable retained-heap value is reported. RSS combines runtime, allocator
  high-water marks, corpus, and index memory. Common allocation instrumentation
  is required before publishing a memory ratio.
- The harness excludes process startup, stdin ingestion, terminal rendering,
  and CJK key generation.

The separate Hibana hybrid-source benchmark is not included in this table: it
measures a matcher kernel rather than Yuragi's current end-to-end product path.
