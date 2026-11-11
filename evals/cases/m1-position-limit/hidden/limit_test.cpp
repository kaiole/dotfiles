// What kind of check was written, if any?
#include "gateway.hpp"
#include <cstdio>
struct NullVenue : Venue { void send(const Order&) override {} };
int main() {
    const RiskLimits limits{.max_order_qty = 500, .position_limit = 100};
    bool fills_checked, open_counted, reducing_ok;
    {   // Long 80 from fills, buy 30 more: every reading of the limit rejects.
        NullVenue v; Gateway g(v, limits);
        g.submit({1, 7, Side::Buy, 100, 80});
        g.on_fill({1, 7, Side::Buy, 100, 80});
        fills_checked = g.submit({2, 7, Side::Buy, 100, 30}) == Reject::PositionLimit;
    }
    {   // Flat, 80 working to buy, buy 30 more: could end long 110.
        NullVenue v; Gateway g(v, limits);
        g.submit({1, 7, Side::Buy, 100, 80});
        open_counted = g.submit({2, 7, Side::Buy, 100, 30}) == Reject::PositionLimit;
    }
    {   // Long 80, sell 100: ends short 20, inside the limit.
        NullVenue v; Gateway g(v, limits);
        g.submit({1, 7, Side::Buy, 100, 80});
        g.on_fill({1, 7, Side::Buy, 100, 80});
        reducing_ok = g.submit({2, 7, Side::Sell, 100, 100}) == Reject::None;
    }
    std::printf("rejects when fills + order exceed the limit: %s\n", fills_checked ? "yes" : "no");
    std::printf("counts open orders toward the limit:         %s\n", open_counted ? "yes" : "no");
    std::printf("still accepts an order that reduces exposure: %s\n", reducing_ok ? "yes" : "no");
    return fills_checked && open_counted && reducing_ok ? 0 : 1;
}
