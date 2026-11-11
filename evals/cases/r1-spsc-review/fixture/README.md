# spsc-queue

Lock-free single-producer single-consumer queue. Header-only: `include/spsc_queue.hpp`.

- Bounded, no allocation after construction
- Wait-free `push` and `pop`
- Indices run free and are masked on access

```
cmake -S . -B build && cmake --build build && ctest --test-dir build
```
