#include "gateway.hpp"

Reject Gateway::submit(const Order& order) {
    if (order.qty <= 0) return Reject::BadQty;
    if (order.price <= 0) return Reject::BadPrice;
    if (order.qty > limits_.max_order_qty) return Reject::OrderTooLarge;

    venue_.send(order);
    positions_.on_order_accepted(order);
    return Reject::None;
}
