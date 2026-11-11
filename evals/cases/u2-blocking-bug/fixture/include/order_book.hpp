#pragma once

#include <cstddef>
#include <cstdint>
#include <list>
#include <map>
#include <optional>
#include <unordered_map>

using OrderId = std::uint64_t;
using Price = std::int64_t;  // ticks
using Qty = std::uint64_t;

enum class Side { Buy, Sell };

struct Order {
    OrderId id;
    Side side;
    Price price;
    Qty qty;
};

class OrderBook {
public:
    // Rests the order at the back of its price level. Returns false if the id
    // is already on the book.
    bool add(const Order& order);

    // Removes a resting order. Returns false if the id is not on the book.
    bool cancel(OrderId id);

    std::optional<Price> best_bid() const;
    std::optional<Price> best_ask() const;
    Qty volume_at(Side side, Price price) const;

private:
    using Level = std::list<Order>;
    using Levels = std::map<Price, Level>;

    struct Locator {
        Side side;
        Price price;
    };

    Levels& levels(Side side) { return side == Side::Buy ? bids_ : asks_; }
    const Levels& levels(Side side) const { return side == Side::Buy ? bids_ : asks_; }

    Levels bids_;
    Levels asks_;
    std::unordered_map<OrderId, Locator> orders_;
};
