#pragma once

#include <cstdint>

// Running statistics over the trades of one symbol.
class TradeStats {
public:
    void on_trade(double price, std::uint64_t qty);

    // 0.0 before the first trade.
    double vwap() const;
    std::uint64_t volume() const { return volume_; }
    std::uint64_t trade_count() const { return trade_count_; }
    double high() const { return high_; }
    double low() const { return low_; }

private:
    double notional_ = 0.0;
    std::uint64_t volume_ = 0;
    std::uint64_t trade_count_ = 0;
    double high_ = 0.0;
    double low_ = 0.0;
};
