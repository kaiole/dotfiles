#pragma once

#include <atomic>
#include <cstddef>
#include <memory>
#include <utility>

// Bounded lock-free queue for one producer thread and one consumer thread.
template <typename T>
class SpscQueue {
public:
    explicit SpscQueue(std::size_t capacity)
        : capacity_(capacity),
          mask_(capacity - 1),
          buffer_(std::make_unique<T[]>(capacity)) {}

    SpscQueue(const SpscQueue&) = delete;
    SpscQueue& operator=(const SpscQueue&) = delete;

    // Producer thread only. Returns false if the queue is full.
    bool push(const T& value) {
        const std::size_t tail = tail_.load(std::memory_order_relaxed);
        const std::size_t head = head_.load(std::memory_order_relaxed);
        if (tail - head == capacity_) return false;

        buffer_[tail & mask_] = value;
        tail_.store(tail + 1, std::memory_order_relaxed);
        return true;
    }

    // Consumer thread only. Returns false if the queue is empty.
    bool pop(T& out) {
        const std::size_t head = head_.load(std::memory_order_relaxed);
        const std::size_t tail = tail_.load(std::memory_order_relaxed);
        if (head == tail) return false;

        head_.store(head + 1, std::memory_order_relaxed);
        out = std::move(buffer_[head & mask_]);
        return true;
    }

    std::size_t size() const {
        return tail_.load(std::memory_order_relaxed) -
               head_.load(std::memory_order_relaxed);
    }

    bool empty() const { return size() == 0; }
    std::size_t capacity() const { return capacity_; }

private:
    const std::size_t capacity_;
    const std::size_t mask_;
    std::unique_ptr<T[]> buffer_;

    std::atomic<std::size_t> head_{0};  // next slot to pop
    std::atomic<std::size_t> tail_{0};  // next slot to push
};
