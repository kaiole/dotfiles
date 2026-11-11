#pragma once

#include "config.hpp"

#include <atomic>
#include <cstdint>

struct Quote {
    std::int64_t bid;
    std::int64_t ask;
};

class TradingLoop {
public:
    TradingLoop(Config initial, std::atomic<bool>& running)
        : config_(initial), running_(running) {}

    void run();

    std::int64_t position() const { return position_; }

private:
    Quote next_quote();
    void on_quote(const Quote& quote);

    Config config_;  // limits in force; only this thread reads them
    std::atomic<bool>& running_;
    std::int64_t position_ = 0;
    std::uint64_t tick_ = 0;
};
