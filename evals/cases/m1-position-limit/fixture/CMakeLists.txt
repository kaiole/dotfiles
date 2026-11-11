cmake_minimum_required(VERSION 3.20)
project(order_gateway CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_compile_options(-Wall -Wextra -Wpedantic)

add_library(gateway src/gateway.cpp src/position_tracker.cpp)
target_include_directories(gateway PUBLIC include)

enable_testing()
add_executable(test_gateway tests/test_gateway.cpp)
target_link_libraries(test_gateway PRIVATE gateway)
add_test(NAME test_gateway COMMAND test_gateway)
