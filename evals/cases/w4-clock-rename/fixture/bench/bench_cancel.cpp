#include "book.hpp"
#include "harness.hpp"

int main() {
    constexpr std::size_t n = 1'000'000;

    Book book;
    for (std::size_t i = 0; i < n; ++i) {
        book.add(i + 1, Side::Buy, 9'990 - static_cast<Price>(i % 50), 100);
    }

    // Cancel in a scattered order so we are not always removing the queue front.
    run_benchmark("cancel", n, [&](std::size_t i) { book.cancel((i * 7919) % n + 1); });
}
