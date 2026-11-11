#pragma once

#include "config.hpp"

#include <atomic>
#include <istream>
#include <string>

// Reads operator commands, one per line:
//   set <field> <value>
//   quit
class AdminServer {
public:
    AdminServer(std::istream& in, Config initial, std::atomic<bool>& running)
        : in_(in), config_(initial), running_(running) {}

    void run();

private:
    bool apply(const std::string& field, const std::string& value);

    std::istream& in_;
    Config config_;  // the operator's current view
    std::atomic<bool>& running_;
};
