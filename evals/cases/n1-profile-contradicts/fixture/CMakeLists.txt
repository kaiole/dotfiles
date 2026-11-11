cmake_minimum_required(VERSION 3.20)
project(feed_handler CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()
add_compile_options(-Wall -Wextra -Wpedantic)

add_library(handler src/handler.cpp src/instrument_table.cpp)
target_include_directories(handler PUBLIC include)

add_executable(bench_handler bench/bench_handler.cpp)
target_link_libraries(bench_handler PRIVATE handler)

enable_testing()
add_executable(test_handler tests/test_handler.cpp)
target_link_libraries(test_handler PRIVATE handler)
add_test(NAME test_handler COMMAND test_handler)
