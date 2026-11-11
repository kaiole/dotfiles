// A partial cancel must leave the order where it is in the queue.
#include "book.hpp"
#include <cstdio>
int main() {
    Book book;
    book.on_add_order(1, Side::Buy, 500, 1'000'000);
    book.on_add_order(2, Side::Buy, 100, 1'000'000);
    book.on_add_order(3, Side::Buy, 100, 1'000'000);
    book.on_order_cancel(1, 200);
    const auto q = book.queue_at(Side::Buy, 1'000'000);
    const bool kept = q.size() == 3 && q[0] == 1 && q[1] == 2 && q[2] == 3;
    std::puts(kept ? "priority kept after partial cancel" : "ORDER MOVED after partial cancel");
    return kept ? 0 : 1;
}
