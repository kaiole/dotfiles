# orderbook-bench

Latency benchmarks for a small limit order book. See `bench/README.md`.

    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
    ./build/bench_add
