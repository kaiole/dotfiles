# feed-handler

Decodes top-of-book quote frames from the feed and keeps the latest quote per
instrument.

    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
    ctest --test-dir build
    ./build/bench_handler

`profiles/` holds callgrind output for `bench_handler`.
