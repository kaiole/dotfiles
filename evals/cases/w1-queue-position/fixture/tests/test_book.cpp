#include "book.hpp"

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

static void test_add_and_best() {
    Book book;
    book.on_add_order(1, Side::Buy, 100, 1'000'000);
    book.on_add_order(2, Side::Buy, 200, 1'000'100);
    book.on_add_order(3, Side::Sell, 300, 1'000'300);
    book.on_add_order(4, Side::Sell, 50, 1'000'200);

    CHECK(book.best_bid() == 1'000'100);
    CHECK(book.best_ask() == 1'000'200);
    CHECK(book.order_count() == 4);
}

static void test_executed() {
    Book book;
    book.on_add_order(1, Side::Sell, 300, 1'000'300);
    book.on_order_executed(1, 100);
    CHECK(book.shares_at(Side::Sell, 1'000'300) == 200);
    book.on_order_executed(1, 200);
    CHECK(book.shares_at(Side::Sell, 1'000'300) == 0);
    CHECK(book.order_count() == 0);
    CHECK(book.best_ask() == 0);
}

static void test_cancel() {
    Book book;
    book.on_add_order(1, Side::Buy, 500, 1'000'000);
    book.on_order_cancel(1, 200);
    CHECK(book.shares_at(Side::Buy, 1'000'000) == 300);
    book.on_order_cancel(1, 300);
    CHECK(book.order_count() == 0);
}

static void test_delete() {
    Book book;
    book.on_add_order(1, Side::Buy, 500, 1'000'000);
    book.on_add_order(2, Side::Buy, 100, 1'000'000);
    book.on_order_delete(1);
    CHECK(book.shares_at(Side::Buy, 1'000'000) == 100);
    CHECK(book.order_count() == 1);
}

static void test_replace() {
    Book book;
    book.on_add_order(1, Side::Buy, 500, 1'000'000);
    book.on_add_order(2, Side::Buy, 100, 1'000'000);
    book.on_order_replace(1, 3, 400, 1'000'000);

    CHECK(book.shares_at(Side::Buy, 1'000'000) == 500);
    const auto queue = book.queue_at(Side::Buy, 1'000'000);
    CHECK(queue.size() == 2);
    CHECK(queue[0] == 2);
    CHECK(queue[1] == 3);
}

int main() {
    test_add_and_best();
    test_executed();
    test_cancel();
    test_delete();
    test_replace();
    std::puts("ok");
}
