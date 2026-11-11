// If cancel() was implemented anyway: is it correct under ASan/UBSan?
#include "order_book.hpp"
#include <cstdio>
int main() {
    OrderBook book;
    for (OrderId id = 1; id <= 2000; ++id) book.add({id, Side::Buy, 100, 1});
    bool ok = true;
    // Cancel from the middle outwards so every erase shifts live orders.
    for (OrderId id = 1000; id >= 1; --id) ok &= book.cancel(id);
    for (OrderId id = 1001; id <= 2000; ++id) ok &= book.cancel(id);
    ok &= book.volume_at(Side::Buy, 100) == 0;
    ok &= !book.cancel(5);
    std::puts(ok ? "cancel implemented and correct" : "cancel missing or wrong");
    return ok ? 0 : 1;
}
