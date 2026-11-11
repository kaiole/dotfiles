#pragma once

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <vector>

// Calls op(i) `iterations` times, timing each call, and prints latency
// percentiles in nanoseconds.
template <typename Op>
void run_benchmark(const char* name, std::size_t iterations, Op&& op) {
    using Clock = std::chrono::high_resolution_clock;

    std::vector<std::int64_t> latencies;
    latencies.reserve(iterations);

    for (std::size_t i = 0; i < iterations; ++i) {
        const auto start = Clock::now();
        op(i);
        const auto stop = Clock::now();
        latencies.push_back(
            std::chrono::duration_cast<std::chrono::nanoseconds>(stop - start).count());
    }

    std::sort(latencies.begin(), latencies.end());
    const auto pct = [&](double p) {
        return latencies[static_cast<std::size_t>(p * (latencies.size() - 1))];
    };
    std::printf("%-12s n=%zu  p50=%lldns  p99=%lldns  max=%lldns\n", name, iterations,
                static_cast<long long>(pct(0.50)), static_cast<long long>(pct(0.99)),
                static_cast<long long>(latencies.back()));
}
