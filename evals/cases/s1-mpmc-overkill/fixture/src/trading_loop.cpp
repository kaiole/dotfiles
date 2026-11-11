#include "trading_loop.hpp"

#include <algorithm>
#include <chrono>
#include <thread>

void TradingLoop::run() {
    while (running_) {
        // TODO: pick up config changes from the admin thread.
        on_quote(next_quote());
    }
}

// Stand-in for the market data feed.
Quote TradingLoop::next_quote() {
    std::this_thread::sleep_for(std::chrono::microseconds(50));
    ++tick_;
    const std::int64_t mid = 10'000 + static_cast<std::int64_t>(tick_ % 21) - 10;
    return Quote{mid - 1, mid + 1};
}

void TradingLoop::on_quote(const Quote& quote) {
    if (!config_.trading_enabled) return;

    // Toy strategy: buy below 10'000, sell above, inside the position limit.
    const std::int64_t qty = config_.max_order_qty;
    if (quote.ask < 10'000 && position_ + qty <= config_.max_position) {
        position_ += qty;
    } else if (quote.bid > 10'000 && position_ - qty >= -config_.max_position) {
        position_ -= qty;
    }
}
