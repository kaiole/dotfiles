#include "parallel_sum.hpp"

#include <cstdio>
#include <cstdlib>
#include <numeric>

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__,    \
                         __LINE__, #cond);                                 \
            std::exit(1);                                                  \
        }                                                                  \
    } while (0)

int main() {
    std::vector<int> data(1'000'003);
    std::iota(data.begin(), data.end(), -500'000);
    const long expected = std::accumulate(data.begin(), data.end(), 0L);

    for (unsigned threads : {1u, 2u, 3u, 8u}) {
        CHECK(parallel_sum(data, threads) == expected);
    }
    CHECK(parallel_sum({}, 4) == 0);
    std::puts("ok");
}
