#include "spsc_queue.hpp"

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

static void test_push_pop() {
    SpscQueue<int> queue(8);
    CHECK(queue.empty());
    for (int i = 0; i < 8; ++i) CHECK(queue.push(i));
    CHECK(!queue.push(99));
    CHECK(queue.size() == 8);

    int value = -1;
    for (int i = 0; i < 8; ++i) {
        CHECK(queue.pop(value));
        CHECK(value == i);
    }
    CHECK(!queue.pop(value));
}

static void test_wraps() {
    SpscQueue<std::string> queue(4);
    std::string value;
    for (int round = 0; round < 100; ++round) {
        CHECK(queue.push("a" + std::to_string(round)));
        CHECK(queue.push("b" + std::to_string(round)));
        CHECK(queue.pop(value));
        CHECK(value == "a" + std::to_string(round));
        CHECK(queue.pop(value));
        CHECK(value == "b" + std::to_string(round));
    }
    CHECK(queue.empty());
}

int main() {
    test_push_pop();
    test_wraps();
    std::puts("ok");
}
