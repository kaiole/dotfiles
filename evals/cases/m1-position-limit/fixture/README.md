# order-gateway

Sits between the strategy and the venue. Validates each order, forwards it,
and keeps per-symbol position state from the venue's acks, fills and cancels.

    cmake -S . -B build && cmake --build build && ctest --test-dir build
