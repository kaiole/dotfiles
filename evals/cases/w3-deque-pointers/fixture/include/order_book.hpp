#pragma once

#include <cstdint>
#include <deque>
#include <map>
#include <optional>

using OrderId = std::uint64_t;
using Price = std::int64_t;  // ticks
using Qty = std::uint32_t;

enum class Side { Buy, Sell };

struct Order {
    OrderId id;
    Side side;
    Price price;
    Qty qty;
};

class OrderBook {
public:
    // Rests the order at the back of its price level.
    void add(const Order& order);

    // Removes a resting order. Returns false if the id is not on the book.
    bool cancel(OrderId id);

    std::optional<Price> best_bid() const;
    std::optional<Price> best_ask() const;
    Qty volume_at(Side side, Price price) const;

private:
    using Level = std::deque<Order>;  // front = oldest = first to match

    std::map<Price, Level> bids_;
    std::map<Price, Level> asks_;
};
