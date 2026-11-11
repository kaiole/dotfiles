#include "order_book.hpp"

void OrderBook::add(const Order& order) {
    auto& levels = order.side == Side::Buy ? bids_ : asks_;
    levels[order.price].push_back(order);
}

bool OrderBook::cancel(OrderId /*id*/) {
    // TODO
    return false;
}

std::optional<Price> OrderBook::best_bid() const {
    if (bids_.empty()) return std::nullopt;
    return bids_.rbegin()->first;
}

std::optional<Price> OrderBook::best_ask() const {
    if (asks_.empty()) return std::nullopt;
    return asks_.begin()->first;
}

Qty OrderBook::volume_at(Side side, Price price) const {
    const auto& levels = side == Side::Buy ? bids_ : asks_;
    auto level = levels.find(price);
    if (level == levels.end()) return 0;

    Qty total = 0;
    for (const Order& order : level->second) total += order.qty;
    return total;
}
