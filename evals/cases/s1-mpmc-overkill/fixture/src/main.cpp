#include "admin_server.hpp"
#include "trading_loop.hpp"

#include <atomic>
#include <cstdio>
#include <iostream>
#include <thread>

int main() {
    std::atomic<bool> running{true};
    const Config initial;

    TradingLoop trading(initial, running);
    AdminServer admin(std::cin, initial, running);

    std::thread trading_thread([&] { trading.run(); });
    admin.run();  // returns on "quit" or end of input
    trading_thread.join();

    std::printf("final position: %lld\n", static_cast<long long>(trading.position()));
}
