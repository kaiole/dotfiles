// Replays a pre-generated stream of quote frames through the handler and
// prints the mean time per message.
//
//     bench_handler [passes]
#include "handler.hpp"
#include "wire.hpp"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <vector>

namespace {

constexpr std::uint32_t kInstruments = 4'000;
constexpr std::size_t kFrames = 1'000'000;
constexpr int kDefaultPasses = 20;

template <typename T>
void write(std::uint8_t* at, T value) {
    std::memcpy(at, &value, sizeof(T));
}

std::vector<std::uint8_t> make_stream() {
    std::vector<std::uint8_t> stream(kFrames * kQuoteFrameSize);
    std::mt19937 rng(7);
    std::uniform_int_distribution<std::uint32_t> pick(0, kInstruments - 1);
    for (std::size_t i = 0; i < kFrames; ++i) {
        std::uint8_t* at = stream.data() + i * kQuoteFrameSize;
        const std::int64_t mid = 10'000 + static_cast<std::int64_t>(rng() % 500);
        write<std::uint16_t>(at, kQuoteFrameSize);
        write<std::uint8_t>(at + 2, 'Q');
        write<std::uint8_t>(at + 3, 0);
        write<std::uint32_t>(at + 4, 1'000 + pick(rng) * 7);
        write<std::uint64_t>(at + 8, i + 1);
        write<std::int64_t>(at + 16, mid - 1);
        write<std::int64_t>(at + 24, mid + 1);
        write<std::uint32_t>(at + 32, 100);
        write<std::uint32_t>(at + 36, 100);
    }
    return stream;
}

}  // namespace

int main(int argc, char** argv) {
    const int passes = argc > 1 ? std::atoi(argv[1]) : kDefaultPasses;

    Handler handler;
    for (std::uint32_t i = 0; i < kInstruments; ++i) handler.add_instrument(1'000 + i * 7);

    std::vector<std::uint8_t> stream = make_stream();

    const auto start = std::chrono::steady_clock::now();
    for (int pass = 0; pass < passes; ++pass) {
        for (std::size_t i = 0; i < kFrames; ++i) {
            std::uint8_t* at = stream.data() + i * kQuoteFrameSize;
            // Keep sequences increasing across passes.
            write<std::uint64_t>(at + 8, static_cast<std::uint64_t>(pass) * kFrames + i + 1);
            handler.on_message({at, kQuoteFrameSize});
        }
    }
    const auto elapsed = std::chrono::steady_clock::now() - start;

    const double total = static_cast<double>(kFrames) * passes;
    const double ns = std::chrono::duration<double, std::nano>(elapsed).count() / total;
    std::printf("%.0f messages, %.1f ns/message, applied %llu, dropped %llu\n", total, ns,
                static_cast<unsigned long long>(handler.applied()),
                static_cast<unsigned long long>(handler.dropped()));
}
