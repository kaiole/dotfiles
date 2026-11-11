#include "book.hpp"

void Book::on_add_order(OrderRef ref, Side side, Shares shares, Price price) {
    Level& level = levels(side)[price];
    level.push_back(Order{ref, side, price, shares});
    orders_[ref] = Locator{side, price, std::prev(level.end())};
}

void Book::on_order_executed(OrderRef ref, Shares executed) {
    auto found = orders_.find(ref);
    if (found == orders_.end()) return;

    Order& order = *found->second.it;
    if (executed >= order.shares) {
        remove(found);
        return;
    }
    order.shares -= executed;
}

void Book::on_order_cancel(OrderRef ref, Shares canceled) {
    auto found = orders_.find(ref);
    if (found == orders_.end()) return;

    Order& order = *found->second.it;
    if (canceled >= order.shares) {
        remove(found);
        return;
    }
    order.shares -= canceled;
}

void Book::on_order_delete(OrderRef ref) {
    auto found = orders_.find(ref);
    if (found == orders_.end()) return;
    remove(found);
}

void Book::on_order_replace(OrderRef old_ref, OrderRef new_ref, Shares shares,
                            Price price) {
    auto found = orders_.find(old_ref);
    if (found == orders_.end()) return;

    const Side side = found->second.side;
    remove(found);
    on_add_order(new_ref, side, shares, price);
}

Price Book::best_bid() const {
    return bids_.empty() ? 0 : bids_.rbegin()->first;
}

Price Book::best_ask() const {
    return asks_.empty() ? 0 : asks_.begin()->first;
}

Shares Book::shares_at(Side side, Price price) const {
    const Levels& side_levels = levels(side);
    auto level = side_levels.find(price);
    if (level == side_levels.end()) return 0;

    Shares total = 0;
    for (const Order& order : level->second) total += order.shares;
    return total;
}

std::vector<OrderRef> Book::queue_at(Side side, Price price) const {
    std::vector<OrderRef> refs;
    const Levels& side_levels = levels(side);
    auto level = side_levels.find(price);
    if (level == side_levels.end()) return refs;

    for (const Order& order : level->second) refs.push_back(order.ref);
    return refs;
}

void Book::remove(std::unordered_map<OrderRef, Locator>::iterator found) {
    const Locator& loc = found->second;
    Levels& side_levels = levels(loc.side);
    auto level = side_levels.find(loc.price);
    level->second.erase(loc.it);
    if (level->second.empty()) side_levels.erase(level);
    orders_.erase(found);
}
