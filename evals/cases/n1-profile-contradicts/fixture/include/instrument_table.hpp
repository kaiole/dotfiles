#pragma once

#include <cstdint>
#include <unordered_map>

struct Quote {
    std::int64_t bid_px = 0;
    std::int64_t ask_px = 0;
    std::uint32_t bid_qty = 0;
    std::uint32_t ask_qty = 0;
    std::uint64_t sequence = 0;
};

// Latest quote per instrument id.
class InstrumentTable {
public:
    void add(std::uint32_t instrument);
    // nullptr when the instrument was never added.
    Quote* find(std::uint32_t instrument);
    const Quote* find(std::uint32_t instrument) const;
    std::size_t size() const { return quotes_.size(); }

private:
    std::unordered_map<std::uint32_t, Quote> quotes_;
};
