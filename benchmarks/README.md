# Benchmarks

No performance benchmark is published before the first real algorithm exists.
When benchmarks are added, record the CPU, OS, Mojo version, compiler options,
dataset provenance, warmup, iterations, statistic, and exact command.

Benchmark programs belong in `bench_*.mojo`. Results are development evidence,
not permanent marketing claims.

The v0.1 benchmark matrix will separate:

- UTF-8 ingestion and candidate framing
- Moji text-view and source-mapping construction
- Yomi representation generation by language mode
- Hibana match scoring and top-K selection
- complete noninteractive process time

Measure at 100, 10,000, and 1,000,000 candidates with short, long, empty, and
no-match queries. Include ASCII paths, mixed Unicode, and licensed/provenanced
CJK fixtures. This separation prevents I/O or representation cost from being
misreported as matcher performance.
