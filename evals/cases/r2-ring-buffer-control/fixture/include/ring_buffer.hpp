#pragma once

#include <array>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>

// Fixed-capacity FIFO. Not thread-safe.
template <typename T, std::size_t N>
class RingBuffer {
    static_assert(std::has_single_bit(N), "N must be a power of two");
    static_assert(N <= (std::size_t{1} << 31), "N must fit the index type");

public:
    // Returns false if the buffer is full.
    bool push(const T& value) {
        if (full()) return false;
        slots_[tail_ & kMask] = value;
        ++tail_;
        return true;
    }

    // Returns the oldest element, or nullopt if the buffer is empty.
    std::optional<T> pop() {
        if (empty()) return std::nullopt;
        T value = std::move(slots_[head_ & kMask]);
        ++head_;
        return value;
    }

    std::size_t size() const { return static_cast<std::uint32_t>(tail_ - head_); }
    bool empty() const { return head_ == tail_; }
    bool full() const { return size() == N; }
    static constexpr std::size_t capacity() { return N; }

private:
    static constexpr std::uint32_t kMask = static_cast<std::uint32_t>(N - 1);

    std::array<T, N> slots_{};
    std::uint32_t head_ = 0;  // total pops
    std::uint32_t tail_ = 0;  // total pushes
};
