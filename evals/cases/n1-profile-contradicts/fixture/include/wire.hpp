#pragma once

#include <cstddef>
#include <cstdint>

// Quote frame, little-endian, packed:
//   u16 length   (whole frame, bytes)
//   u8  type     ('Q')
//   u8  flags
//   u32 instrument
//   u64 sequence
//   i64 bid_px   (ticks)
//   i64 ask_px
//   u32 bid_qty
//   u32 ask_qty
inline constexpr std::size_t kQuoteFrameSize = 40;

// Largest frame the feed can send (jumbo frame payload).
inline constexpr std::size_t kMaxFrameSize = 9000;
