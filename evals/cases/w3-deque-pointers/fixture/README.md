# matching-engine

Price-time priority limit order book. Work in progress: resting orders and
depth queries work, cancel is next, matching after that.

    cmake -S . -B build && cmake --build build && ctest --test-dir build
