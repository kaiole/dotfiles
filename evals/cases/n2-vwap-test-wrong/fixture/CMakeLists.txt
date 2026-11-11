cmake_minimum_required(VERSION 3.20)
project(md_stats CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_compile_options(-Wall -Wextra -Wpedantic)

add_library(md_stats src/vwap.cpp)
target_include_directories(md_stats PUBLIC include)

enable_testing()
add_executable(test_trade_stats tests/test_trade_stats.cpp)
target_link_libraries(test_trade_stats PRIVATE md_stats)
add_test(NAME test_trade_stats COMMAND test_trade_stats)
