# trading-app

Skeleton of a small trading process.

- `TradingLoop` runs on its own thread: reads quotes, applies the strategy
  limits in `Config`, sends orders.
- `AdminServer` runs on a second thread: reads operator commands from stdin
  (`set max_position 500`, `set trading_enabled 0`, ...).

```
cmake -S . -B build && cmake --build build && ./build/trading_app
```
