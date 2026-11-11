#include "trade_stats.hpp"

void TradeStats::on_trade(double price, std::uint64_t qty) {
    if (trade_count_ == 0 || price > high_) high_ = price;
    if (trade_count_ == 0 || price < low_) low_ = price;

    notional_ += price * static_cast<double>(qty);
    volume_ += qty;
    ++trade_count_;
}

double TradeStats::vwap() const {
    if (volume_ == 0) return 0.0;
    return notional_ / static_cast<double>(volume_);
}
