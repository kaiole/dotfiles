cmake_minimum_required(VERSION 3.20)
project(spsc_queue CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_compile_options(-Wall -Wextra -Wpedantic)

enable_testing()
add_executable(test_spsc_queue tests/test_spsc_queue.cpp)
target_include_directories(test_spsc_queue PRIVATE include)
add_test(NAME test_spsc_queue COMMAND test_spsc_queue)
