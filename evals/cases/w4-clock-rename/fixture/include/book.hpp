#pragma once

#include <cstdint>
#include <list>
#include <map>
#include <unordered_map>

using OrderId = std::uint64_t;
using Price = std::int64_t;
using Qty = std::uint32_t;

enum class Side { Buy, Sell };

class Book {
public:
    void add(OrderId id, Side side, Price price, Qty qty) {
        auto& level = (side == Side::Buy ? bids_ : asks_)[price];
        level.push_back({id, qty});
        orders_[id] = {side, price, std::prev(level.end())};
    }

    bool cancel(OrderId id) {
        auto found = orders_.find(id);
        if (found == orders_.end()) return false;
        auto& levels = found->second.side == Side::Buy ? bids_ : asks_;
        auto level = levels.find(found->second.price);
        level->second.erase(found->second.it);
        if (level->second.empty()) levels.erase(level);
        orders_.erase(found);
        return true;
    }

    // Takes up to `qty` from the best levels of `side`. Returns the filled quantity.
    Qty match(Side side, Qty qty) {
        auto& levels = side == Side::Buy ? bids_ : asks_;
        Qty filled = 0;
        while (qty > 0 && !levels.empty()) {
            auto level = side == Side::Buy ? std::prev(levels.end()) : levels.begin();
            auto& resting = level->second.front();
            const Qty take = resting.qty < qty ? resting.qty : qty;
            resting.qty -= take;
            qty -= take;
            filled += take;
            if (resting.qty == 0) {
                orders_.erase(resting.id);
                level->second.pop_front();
                if (level->second.empty()) levels.erase(level);
            }
        }
        return filled;
    }

    std::size_t size() const { return orders_.size(); }

private:
    struct Resting {
        OrderId id;
        Qty qty;
    };
    using Level = std::list<Resting>;
    struct Locator {
        Side side;
        Price price;
        Level::iterator it;
    };

    std::map<Price, Level> bids_;
    std::map<Price, Level> asks_;
    std::unordered_map<OrderId, Locator> orders_;
};
