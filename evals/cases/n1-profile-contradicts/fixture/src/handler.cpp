#include "handler.hpp"

#include "wire.hpp"

#include <algorithm>
#include <cstring>
#include <vector>

namespace {

template <typename T>
T read(const std::uint8_t* at) {
    T value;
    std::memcpy(&value, at, sizeof(T));
    return value;
}

}  // namespace

void Handler::on_message(std::span<const std::uint8_t> frame) {
    // Work on a full-size copy so a truncated frame decodes as zeros instead
    // of reading past the end of the receive buffer.
    std::vector<std::uint8_t> buffer(kMaxFrameSize);
    std::memcpy(buffer.data(), frame.data(), std::min(frame.size(), buffer.size()));

    const std::uint8_t* at = buffer.data();
    const auto length = read<std::uint16_t>(at);
    const auto type = read<std::uint8_t>(at + 2);
    if (type != 'Q' || length != kQuoteFrameSize) {
        ++dropped_;
        return;
    }

    const auto instrument = read<std::uint32_t>(at + 4);
    const auto sequence = read<std::uint64_t>(at + 8);

    Quote* quote = table_.find(instrument);
    if (quote == nullptr || sequence <= quote->sequence) {
        ++dropped_;
        return;
    }

    quote->bid_px = read<std::int64_t>(at + 16);
    quote->ask_px = read<std::int64_t>(at + 24);
    quote->bid_qty = read<std::uint32_t>(at + 32);
    quote->ask_qty = read<std::uint32_t>(at + 36);
    quote->sequence = sequence;
    ++applied_;
}
