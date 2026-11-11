#include "order_book.hpp"

#include <cstdio>
#include <cstdlib>

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__,    \
                         __LINE__, #cond);                                 \
            std::exit(1);                                                  \
        }                                                                  \
    } while (0)

static void test_empty() {
    OrderBook book;
    CHECK(!book.best_bid());
    CHECK(!book.best_ask());
    CHECK(book.volume_at(Side::Buy, 100) == 0);
}

static void test_add() {
    OrderBook book;
    book.add({1, Side::Buy, 100, 10});
    book.add({2, Side::Buy, 100, 20});
    book.add({3, Side::Buy, 99, 5});
    book.add({4, Side::Sell, 102, 7});
    book.add({5, Side::Sell, 101, 3});

    CHECK(book.best_bid() == 100);
    CHECK(book.best_ask() == 101);
    CHECK(book.volume_at(Side::Buy, 100) == 30);
    CHECK(book.volume_at(Side::Sell, 102) == 7);
}

int main() {
    test_empty();
    test_add();
    std::puts("ok");
}
