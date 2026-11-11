#include "gateway.hpp"

#include <cstdio>
#include <cstdlib>
#include <vector>

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__,    \
                         __LINE__, #cond);                                 \
            std::exit(1);                                                  \
        }                                                                  \
    } while (0)

struct FakeVenue : Venue {
    std::vector<Order> sent;
    void send(const Order& order) override { sent.push_back(order); }
};

static void test_validation() {
    FakeVenue venue;
    Gateway gateway(venue, RiskLimits{.max_order_qty = 500, .position_limit = 2'000});

    CHECK(gateway.submit({1, 7, Side::Buy, 100, 0}) == Reject::BadQty);
    CHECK(gateway.submit({2, 7, Side::Buy, 0, 10}) == Reject::BadPrice);
    CHECK(gateway.submit({3, 7, Side::Buy, 100, 501}) == Reject::OrderTooLarge);
    CHECK(venue.sent.empty());

    CHECK(gateway.submit({4, 7, Side::Buy, 100, 500}) == Reject::None);
    CHECK(venue.sent.size() == 1);
}

static void test_position_tracking() {
    FakeVenue venue;
    Gateway gateway(venue, RiskLimits{});

    const Order buy{1, 7, Side::Buy, 100, 300};
    const Order sell{2, 7, Side::Sell, 101, 200};
    CHECK(gateway.submit(buy) == Reject::None);
    CHECK(gateway.submit(sell) == Reject::None);
    CHECK(gateway.positions().open_buy_qty(7) == 300);
    CHECK(gateway.positions().open_sell_qty(7) == 200);
    CHECK(gateway.positions().position(7) == 0);

    gateway.on_fill({1, 7, Side::Buy, 100, 120});
    CHECK(gateway.positions().position(7) == 120);
    CHECK(gateway.positions().open_buy_qty(7) == 180);

    gateway.on_cancel(buy, 180);
    CHECK(gateway.positions().open_buy_qty(7) == 0);

    gateway.on_fill({2, 7, Side::Sell, 101, 200});
    CHECK(gateway.positions().position(7) == -80);
    CHECK(gateway.positions().position(8) == 0);
}

int main() {
    test_validation();
    test_position_tracking();
    std::puts("ok");
}
