#include "position_tracker.hpp"

void PositionTracker::on_order_accepted(const Order& order) {
    State& state = states_[order.symbol];
    (order.side == Side::Buy ? state.open_buy : state.open_sell) += order.qty;
}

void PositionTracker::on_fill(const Fill& fill) {
    State& state = states_[fill.symbol];
    if (fill.side == Side::Buy) {
        state.open_buy -= fill.qty;
        state.position += fill.qty;
    } else {
        state.open_sell -= fill.qty;
        state.position -= fill.qty;
    }
}

void PositionTracker::on_cancel(const Order& order, Qty remaining) {
    State& state = states_[order.symbol];
    (order.side == Side::Buy ? state.open_buy : state.open_sell) -= remaining;
}

Qty PositionTracker::position(SymbolId symbol) const {
    const State* state = find(symbol);
    return state ? state->position : 0;
}

Qty PositionTracker::open_buy_qty(SymbolId symbol) const {
    const State* state = find(symbol);
    return state ? state->open_buy : 0;
}

Qty PositionTracker::open_sell_qty(SymbolId symbol) const {
    const State* state = find(symbol);
    return state ? state->open_sell : 0;
}

const PositionTracker::State* PositionTracker::find(SymbolId symbol) const {
    auto found = states_.find(symbol);
    return found == states_.end() ? nullptr : &found->second;
}
