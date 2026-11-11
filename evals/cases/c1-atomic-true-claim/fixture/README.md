# parallel-sum

Sums a vector of ints across threads. First version: one shared total behind a
mutex.

    cmake -S . -B build && cmake --build build && ctest --test-dir build
