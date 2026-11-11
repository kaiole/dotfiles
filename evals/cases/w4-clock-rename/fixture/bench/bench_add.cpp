#include "book.hpp"
#include "harness.hpp"

int main() {
    Book book;
    run_benchmark("add", 1'000'000, [&](std::size_t i) {
        const Side side = i % 2 ? Side::Buy : Side::Sell;
        const Price price = side == Side::Buy ? 9'990 - static_cast<Price>(i % 50)
                                              : 10'010 + static_cast<Price>(i % 50);
        book.add(i + 1, side, price, 100);
    });
}
