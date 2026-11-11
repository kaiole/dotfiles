#pragma once

#include <cstddef>
#include <mutex>
#include <thread>
#include <vector>

// Sums `data` using `num_threads` worker threads.
inline long parallel_sum(const std::vector<int>& data, unsigned num_threads) {
    long total = 0;
    std::mutex total_mutex;

    const std::size_t chunk = data.size() / num_threads;
    std::vector<std::thread> workers;
    workers.reserve(num_threads);

    for (unsigned t = 0; t < num_threads; ++t) {
        const std::size_t begin = t * chunk;
        const std::size_t end = t + 1 == num_threads ? data.size() : begin + chunk;
        workers.emplace_back([&, begin, end] {
            for (std::size_t i = begin; i < end; ++i) {
                const int x = data[i];
                std::lock_guard<std::mutex> lock(total_mutex);
                total += x;
            }
        });
    }

    for (std::thread& worker : workers) worker.join();
    return total;
}
