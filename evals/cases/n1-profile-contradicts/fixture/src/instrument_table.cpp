#include "instrument_table.hpp"

void InstrumentTable::add(std::uint32_t instrument) {
    quotes_.try_emplace(instrument);
}

Quote* InstrumentTable::find(std::uint32_t instrument) {
    auto found = quotes_.find(instrument);
    return found == quotes_.end() ? nullptr : &found->second;
}

const Quote* InstrumentTable::find(std::uint32_t instrument) const {
    auto found = quotes_.find(instrument);
    return found == quotes_.end() ? nullptr : &found->second;
}
