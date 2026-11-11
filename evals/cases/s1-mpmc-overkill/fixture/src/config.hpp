#pragma once

#include <cstdint>

// Strategy limits. Set at startup; the operator can change them while running.
struct Config {
    std::int64_t max_position = 1'000;
    std::uint32_t max_order_qty = 100;
    std::uint32_t price_band_bps = 50;
    bool trading_enabled = true;
};
