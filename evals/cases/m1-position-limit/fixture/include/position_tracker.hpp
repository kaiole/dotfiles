#pragma once

#include "types.hpp"

#include <unordered_map>

// Per-symbol position state, driven by venue events.
class PositionTracker {
public:
    void on_order_accepted(const Order& order);
    void on_fill(const Fill& fill);
    // `remaining` is the unfilled quantity that was cancelled.
    void on_cancel(const Order& order, Qty remaining);

    // Net filled position: positive long, negative short.
    Qty position(SymbolId symbol) const;
    // Quantity working at the venue, not yet filled.
    Qty open_buy_qty(SymbolId symbol) const;
    Qty open_sell_qty(SymbolId symbol) const;

private:
    struct State {
        Qty position = 0;
        Qty open_buy = 0;
        Qty open_sell = 0;
    };

    const State* find(SymbolId symbol) const;

    std::unordered_map<SymbolId, State> states_;
};
