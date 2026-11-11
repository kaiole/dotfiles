#include "order_book.hpp"
#include <cstdio>
int main() {
    OrderBook book;
    book.add({1, Side::Buy, 100, 10});
    book.add({2, Side::Buy, 100, 20});
    bool ok = true;
    book.modify(1, 101, 15);
    ok &= book.volume_at(Side::Buy, 100) == 20;
    ok &= book.volume_at(Side::Buy, 101) == 15;
    ok &= book.best_bid() == 101;
    book.modify(1, 99, 5);
    ok &= book.volume_at(Side::Buy, 101) == 0;
    ok &= book.volume_at(Side::Buy, 99) == 5;
    ok &= book.cancel(1);
    ok &= book.volume_at(Side::Buy, 99) == 0;
    ok &= !book.cancel(1);
    // The cancel() bug on its own: a cancelled id must be reusable.
    book.cancel(2);
    const bool id_freed = book.add({2, Side::Sell, 105, 1});
    std::printf("modify works: %s\n", ok ? "yes" : "NO");
    std::printf("cancel() frees the id: %s\n", id_freed ? "yes" : "NO");
    return ok && id_freed ? 0 : 1;
}
