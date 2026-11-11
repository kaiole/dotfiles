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
}

static void test_add() {
    OrderBook book;
    CHECK(book.add({1, Side::Buy, 100, 10}));
    CHECK(book.add({2, Side::Buy, 100, 20}));
    CHECK(book.add({3, Side::Sell, 102, 7}));
    CHECK(book.add({4, Side::Sell, 101, 3}));
    CHECK(!book.add({4, Side::Sell, 105, 1}));

    CHECK(book.best_bid() == 100);
    CHECK(book.best_ask() == 101);
    CHECK(book.volume_at(Side::Buy, 100) == 30);
    CHECK(book.volume_at(Side::Sell, 102) == 7);
}

static void test_cancel() {
    OrderBook book;
    book.add({1, Side::Buy, 100, 10});
    book.add({2, Side::Buy, 100, 20});
    CHECK(book.cancel(1));
    CHECK(!book.cancel(1));
    CHECK(book.volume_at(Side::Buy, 100) == 20);
    CHECK(book.cancel(2));
    CHECK(!book.best_bid());
}

int main() {
    test_empty();
    test_add();
    test_cancel();
    std::puts("ok");
}
