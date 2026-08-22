# CJK search and profiling protocol

`cjk-search-v1` is the release comparison for prepared direct and explicit
language search. It measures application orchestration, not only Yomi key
generation or Hibana's inner matcher.

## Required cases

Use `N = 10,000` and `N = 100,000`, with result limit 20. Generate candidates
in source-index order with the following exact formulas; do not randomize,
shuffle, normalize, or append an index:

- direct corpus candidate `i` is
  `workspace/pkg-{i % 97}/src/component-{i}/view.mojo`, exactly as in
  `plain-search-v1`;
- Chinese candidate `i` is `北京大学` when `i % 10 == 0`, otherwise `上海站`;
- Japanese candidate `i` is `カメラ` when `i % 10 == 0`, otherwise `テレビ`;
- Korean candidate `i` is `한글` when `i % 10 == 0`, otherwise `서울`.

Candidate bytes exclude a framing delimiter. The exact aggregate sizes are:

| Corpus | 10,000 candidates | 100,000 candidates |
| --- | ---: | ---: |
| direct | 447,851 | 4,578,580 |
| Chinese | 93,000 | 930,000 |
| Japanese | 90,000 | 900,000 |
| Korean | 60,000 | 600,000 |

The required queries and results are:

| Mode | Candidate | Query | Contract |
| --- | --- | --- | --- |
| `auto` | direct corpus | `pkgsrcview` | `N` matches; retained indices `0,1,2,3,4,5,6,7,8,9,97,98,99,10,11,12,13,14,15,16` |
| `auto` | Chinese corpus | `bjdx` | zero matches; auto is direct-only |
| `zh` | Chinese corpus | `bjdx` | `N / 10` matches; first indices `0,10,...,190` |
| `ja` | Japanese corpus | `kamera` | `N / 10` matches; first indices `0,10,...,190` |
| `ko` | Korean corpus | `hangeul` | `N / 10` matches; first indices `0,10,...,190` |

The harness must validate aggregate UTF-8 bytes before timing. It must also
print the protocol name, size, mode, query, preparation checksum, result
checksum, exact match count, retained source indices, winning key kinds, and
the counters below. Define each checksum algorithm in the harness source and
keep it versioned with the protocol. A semantic mismatch fails the run before
timing is reported.

General Japanese Kanji readings are deliberately excluded. They require a
licensed provider, so `日本語`/`nihongo` is a negative fixture rather than a
performance case.

## Sampling

Compile an optimized executable with stable Mojo 1.0.0. Preparation samples
construct and consume a fresh index. Search samples reuse one prepared index
and force a complete scan; they do not include corpus construction or index
preparation. Run three unreported warmups followed by 31 independent measured
samples per `(mode, size, query)`.
Report nearest-rank p50 and p95 in milliseconds; never publish only the fastest
sample. Record:

- CPU, physical core count, OS, compiler version, and exact commit;
- corpus version, candidate count, UTF-8 byte count, and result limit;
- preparation p50/p95 separately from query p50/p95;
- candidates scanned, compatible key pairs scored, positions reconstructed,
  exact match count, and checksum;
- thread count and whether coarse parallelism was enabled.

The release target on the Apple M4 reference host is under 100 ms p50 and
150 ms p95 for the agreed 100,000-candidate search. The existing 10,000-row
plain-search workload must not regress by more than 5% against the recorded
pre-change median. These are release engineering thresholds on one reference
host, not portable latency promises.

The checked-in optimized harness implements this generator and is built and run
through the locked task:

```sh
pixi run --locked bench-cjk
```

Only numbers emitted by that task for a recorded exact commit are publishable
as `cjk-search-v1` evidence.

## Profiling

Profile the optimized executable outside the timed samples. On macOS, use
`sample` or Instruments; on Linux, use `perf record`/`perf report` when runner
permissions allow it. Keep sampling duration, command line, corpus, query, and
commit beside the profile.

Attribute time separately to:

1. candidate/key preparation and allocation;
2. compatible score-only scans;
3. bounded top-K maintenance;
4. finalist position reconstruction and source projection;
5. interactive model construction and ownership transfer.

Optimize measured ownership, storage, and allocation costs first. Hibana's
fuzzy dynamic program has loop-carried state and divergent Unicode exits, and a
prior folded SIMD cache regressed dense matching. SIMD is acceptable only if a
new profile isolates a fixed-width independent kernel and differential tests
plus this 31-sample protocol demonstrate a repeatable improvement on all
supported targets.

## Comparison limits

- Direct and phonetic matching have different key counts; compare like modes.
- Yuru and Yuragi do not use identical scores, so compare workloads and
  cardinality contracts rather than rank values.
- Yuru is parallel at its large-corpus threshold; report its one-thread result
  alongside the default result when making implementation comparisons.
- Process startup, stdin ingestion, terminal I/O, and retained heap are separate
  measurements and must not be folded into an in-process search latency claim.
