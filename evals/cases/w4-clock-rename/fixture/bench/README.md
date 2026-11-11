# Benchmarks

Each benchmark calls `run_benchmark(name, iterations, op)` from `harness.hpp`.
The harness times every call to `op` on its own and prints the p50, p99 and
max latency in nanoseconds.

| Binary | Operation |
| --- | --- |
| `bench_add` | rest a new order |
| `bench_cancel` | cancel a resting order |
| `bench_match` | take liquidity from the best level |
