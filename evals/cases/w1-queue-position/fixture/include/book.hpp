#pragma once

#include <cstddef>
#include <cstdint>
#include <list>
#include <map>
#include <unordered_map>
#include <vector>

using OrderRef = std::uint64_t;
using Price = std::uint32_t;  // ITCH price: 4 implied decimal places
using Shares = std::uint32_t;

enum class Side : char { Buy = 'B', Sell = 'S' };

struct Order {
    OrderRef ref;
    Side side;
    Price price;
    Shares shares;
};

// One symbol's book, driven by ITCH 5.0 order messages.
class Book {
public:
    void on_add_order(OrderRef ref, Side side, Shares shares, Price price);  // A, F
    void on_order_executed(OrderRef ref, Shares executed);                   // E, C
    void on_order_cancel(OrderRef ref, Shares canceled);                     // X
    void on_order_delete(OrderRef ref);                                      // D
    void on_order_replace(OrderRef old_ref, OrderRef new_ref, Shares shares,
                          Price price);                                      // U

    // 0 when the side is empty.
    Price best_bid() const;
    Price best_ask() const;

    Shares shares_at(Side side, Price price) const;
    // Order references resting at a price, front of the queue first.
    std::vector<OrderRef> queue_at(Side side, Price price) const;
    std::size_t order_count() const { return orders_.size(); }

private:
    using Level = std::list<Order>;
    using Levels = std::map<Price, Level>;

    struct Locator {
        Side side;
        Price price;
        Level::iterator it;
    };

    Levels& levels(Side side) { return side == Side::Buy ? bids_ : asks_; }
    const Levels& levels(Side side) const { return side == Side::Buy ? bids_ : asks_; }
    void remove(std::unordered_map<OrderRef, Locator>::iterator found);

    Levels bids_;
    Levels asks_;
    std::unordered_map<OrderRef, Locator> orders_;
};
