#include "order_book.hpp"

bool OrderBook::add(const Order& order) {
    if (orders_.contains(order.id)) return false;

    Level& level = levels(order.side)[order.price];
    level.push_back(order);
    orders_[order.id] = Locator{order.side, order.price};
    return true;
}

bool OrderBook::cancel(OrderId id) {
    auto found = orders_.find(id);
    if (found == orders_.end()) return false;

    const Locator& loc = found->second;
    Levels& side_levels = levels(loc.side);
    auto level = side_levels.find(loc.price);
    if (level == side_levels.end()) return false;

    const auto removed = std::erase_if(
        level->second, [id](const Order& order) { return order.id == id; });
    if (level->second.empty()) side_levels.erase(level);
    return removed > 0;
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
    const Levels& side_levels = levels(side);
    auto level = side_levels.find(price);
    if (level == side_levels.end()) return 0;

    Qty total = 0;
    for (const Order& order : level->second) total += order.qty;
    return total;
}
