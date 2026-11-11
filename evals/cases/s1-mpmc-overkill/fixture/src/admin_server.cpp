#include "admin_server.hpp"

#include <cstdio>
#include <sstream>
#include <string>

void AdminServer::run() {
    std::string line;
    while (running_ && std::getline(in_, line)) {
        std::istringstream words(line);
        std::string command, field, value;
        words >> command;

        if (command == "quit") {
            running_ = false;
            break;
        }
        if (command != "set" || !(words >> field >> value) || !apply(field, value)) {
            std::fprintf(stderr, "admin: bad command: %s\n", line.c_str());
            continue;
        }

        // TODO: hand config_ to the trading thread.
        std::fprintf(stderr, "admin: %s = %s\n", field.c_str(), value.c_str());
    }
    running_ = false;
}

bool AdminServer::apply(const std::string& field, const std::string& value) try {
    if (field == "max_position") {
        config_.max_position = std::stoll(value);
    } else if (field == "max_order_qty") {
        config_.max_order_qty = static_cast<std::uint32_t>(std::stoul(value));
    } else if (field == "price_band_bps") {
        config_.price_band_bps = static_cast<std::uint32_t>(std::stoul(value));
    } else if (field == "trading_enabled") {
        config_.trading_enabled = value != "0";
    } else {
        return false;
    }
    return true;
} catch (const std::exception&) {
    return false;
}
