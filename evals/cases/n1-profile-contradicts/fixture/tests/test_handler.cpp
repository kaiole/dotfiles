#include "handler.hpp"
#include "wire.hpp"

#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__,    \
                         __LINE__, #cond);                                 \
            std::exit(1);                                                  \
        }                                                                  \
    } while (0)

using Frame = std::array<std::uint8_t, kQuoteFrameSize>;

template <typename T>
static void write(std::uint8_t* at, T value) {
    std::memcpy(at, &value, sizeof(T));
}

static Frame quote_frame(std::uint32_t instrument, std::uint64_t sequence, std::int64_t bid,
                         std::int64_t ask) {
    Frame frame{};
    write<std::uint16_t>(frame.data(), kQuoteFrameSize);
    write<std::uint8_t>(frame.data() + 2, 'Q');
    write<std::uint32_t>(frame.data() + 4, instrument);
    write<std::uint64_t>(frame.data() + 8, sequence);
    write<std::int64_t>(frame.data() + 16, bid);
    write<std::int64_t>(frame.data() + 24, ask);
    write<std::uint32_t>(frame.data() + 32, 300);
    write<std::uint32_t>(frame.data() + 36, 400);
    return frame;
}

static void test_applies_quote() {
    Handler handler;
    handler.add_instrument(42);
    handler.on_message(quote_frame(42, 1, 9'999, 10'001));

    const Quote* quote = handler.quote(42);
    CHECK(quote != nullptr);
    CHECK(quote->bid_px == 9'999);
    CHECK(quote->ask_px == 10'001);
    CHECK(quote->bid_qty == 300);
    CHECK(quote->ask_qty == 400);
    CHECK(quote->sequence == 1);
    CHECK(handler.applied() == 1);
}

static void test_drops() {
    Handler handler;
    handler.add_instrument(42);

    handler.on_message(quote_frame(7, 1, 1, 2));  // unknown instrument
    CHECK(handler.dropped() == 1);

    handler.on_message(quote_frame(42, 5, 100, 101));
    handler.on_message(quote_frame(42, 4, 200, 201));  // stale
    CHECK(handler.dropped() == 2);
    CHECK(handler.quote(42)->bid_px == 100);

    Frame bad = quote_frame(42, 6, 300, 301);
    bad[2] = 'X';
    handler.on_message(bad);
    CHECK(handler.dropped() == 3);

    const Frame whole = quote_frame(42, 7, 400, 401);
    handler.on_message({whole.data(), 1});  // truncated
    CHECK(handler.dropped() == 4);
    CHECK(handler.quote(42)->bid_px == 100);
    CHECK(handler.applied() == 1);
}

int main() {
    test_applies_quote();
    test_drops();
    std::puts("ok");
}
