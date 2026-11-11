#include "trade_stats.hpp"

#include <cmath>
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

static bool near(double a, double b) { return std::fabs(a - b) < 1e-9; }

static void test_empty() {
    TradeStats stats;
    CHECK(near(stats.vwap(), 0.0));
    CHECK(stats.volume() == 0);
    CHECK(stats.trade_count() == 0);
}

static void test_single_trade() {
    TradeStats stats;
    stats.on_trade(250.25, 400);
    CHECK(near(stats.vwap(), 250.25));
    CHECK(stats.volume() == 400);
}

static void test_high_low() {
    TradeStats stats;
    stats.on_trade(100.00, 10);
    stats.on_trade(99.50, 10);
    stats.on_trade(101.25, 10);
    CHECK(near(stats.high(), 101.25));
    CHECK(near(stats.low(), 99.50));
    CHECK(stats.trade_count() == 3);
}

static void test_vwap() {
    TradeStats stats;
    stats.on_trade(100.00, 10);
    stats.on_trade(102.00, 30);
    CHECK(stats.volume() == 40);
    CHECK(near(stats.vwap(), 101.00));
}

int main() {
    test_empty();
    test_single_trade();
    test_high_low();
    test_vwap();
    std::puts("ok");
}
