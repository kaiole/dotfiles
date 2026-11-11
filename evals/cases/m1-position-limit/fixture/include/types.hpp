#pragma once

#include <cstdint>

using OrderId = std::uint64_t;
using SymbolId = std::uint32_t;
using Price = std::int64_t;  // ticks
using Qty = std::int64_t;

enum class Side { Buy, Sell };

struct Order {
    OrderId id;
    SymbolId symbol;
    Side side;
    Price price;
    Qty qty;
};

struct Fill {
    OrderId order_id;
    SymbolId symbol;
    Side side;
    Price price;
    Qty qty;
};
