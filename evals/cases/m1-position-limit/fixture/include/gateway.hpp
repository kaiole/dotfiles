#pragma once

#include "position_tracker.hpp"
#include "types.hpp"

enum class Reject {
    None,
    BadQty,
    BadPrice,
    OrderTooLarge,
    PositionLimit,
};

struct RiskLimits {
    Qty max_order_qty = 500;
    Qty position_limit = 2'000;  // per symbol, absolute
};

// Where accepted orders go. The real one writes to the venue session.
class Venue {
public:
    virtual ~Venue() = default;
    virtual void send(const Order& order) = 0;
};

class Gateway {
public:
    Gateway(Venue& venue, RiskLimits limits) : venue_(venue), limits_(limits) {}

    // Validates the order and, if it passes, sends it to the venue.
    Reject submit(const Order& order);

    // Venue callbacks.
    void on_fill(const Fill& fill) { positions_.on_fill(fill); }
    void on_cancel(const Order& order, Qty remaining) { positions_.on_cancel(order, remaining); }

    const PositionTracker& positions() const { return positions_; }

private:
    Venue& venue_;
    RiskLimits limits_;
    PositionTracker positions_;
};
