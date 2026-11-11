#pragma once

#include "instrument_table.hpp"

#include <cstdint>
#include <span>

class Handler {
public:
    void add_instrument(std::uint32_t instrument) { table_.add(instrument); }

    // One frame from the feed. Frames for unknown instruments, out-of-order
    // frames and malformed frames are counted and dropped.
    void on_message(std::span<const std::uint8_t> frame);

    const Quote* quote(std::uint32_t instrument) const { return table_.find(instrument); }
    std::uint64_t applied() const { return applied_; }
    std::uint64_t dropped() const { return dropped_; }

private:
    InstrumentTable table_;
    std::uint64_t applied_ = 0;
    std::uint64_t dropped_ = 0;
};
