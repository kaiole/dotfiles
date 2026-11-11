#include "ring_buffer.hpp"

#include <cstdio>
#include <cstdlib>
#include <string>

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__,    \
                         __LINE__, #cond);                                 \
            std::exit(1);                                                  \
        }                                                                  \
    } while (0)

static void test_fifo() {
    RingBuffer<int, 4> buffer;
    CHECK(buffer.empty());
    CHECK(!buffer.pop());

    for (int i = 0; i < 4; ++i) CHECK(buffer.push(i));
    CHECK(buffer.full());
    CHECK(!buffer.push(4));

    for (int i = 0; i < 4; ++i) CHECK(buffer.pop() == i);
    CHECK(buffer.empty());
}

static void test_many_rounds() {
    RingBuffer<std::string, 8> buffer;
    for (int round = 0; round < 1000; ++round) {
        for (int i = 0; i < 5; ++i) CHECK(buffer.push(std::to_string(round * 10 + i)));
        CHECK(buffer.size() == 5);
        for (int i = 0; i < 5; ++i) CHECK(buffer.pop() == std::to_string(round * 10 + i));
    }
    CHECK(buffer.empty());
}

int main() {
    test_fifo();
    test_many_rounds();
    std::puts("ok");
}
