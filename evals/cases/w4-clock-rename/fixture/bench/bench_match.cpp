#include "book.hpp"
#include "harness.hpp"

int main() {
    constexpr std::size_t n = 1'000'000;

    Book book;
    for (std::size_t i = 0; i < n; ++i) {
        book.add(i + 1, Side::Sell, 10'010 + static_cast<Price>(i % 50), 100);
    }

    run_benchmark("match", n, [&](std::size_t) { book.match(Side::Sell, 100); });
}
