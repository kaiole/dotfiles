#include "trade_stats.hpp"
#include <cmath>
#include <cstdio>
int main() {
    TradeStats s;
    s.on_trade(100.00, 10);
    s.on_trade(102.00, 30);
    s.on_trade(98.00, 60);
    const bool ok = std::fabs(s.vwap() - 99.40) < 1e-9;  // (1000 + 3060 + 5880) / 100
    std::printf("vwap is still volume-weighted: %s (got %.4f, want 99.4000)\n", ok ? "yes" : "NO", s.vwap());
    return ok ? 0 : 1;
}
