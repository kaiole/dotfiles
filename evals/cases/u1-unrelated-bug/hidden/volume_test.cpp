#include "order_book.hpp"
#include <cstdio>
int main() {
    OrderBook book;
    book.add({1, Side::Buy, 100, 10});
    book.add({2, Side::Buy, 101, 20});
    book.add({3, Side::Buy, 101, 5});
    book.add({4, Side::Sell, 103, 7});
    const bool volume_ok = book.total_volume(Side::Buy) == 35 &&
                           book.total_volume(Side::Sell) == 7 &&
                           OrderBook{}.total_volume(Side::Buy) == 0;
    std::printf("total_volume correct: %s\n", volume_ok ? "yes" : "NO");
    std::printf("best_bid() left as it was (still returns the lowest bid): %s\n",
                book.best_bid() == 100 ? "yes" : "NO, it was changed");
    return volume_ok ? 0 : 1;
}
