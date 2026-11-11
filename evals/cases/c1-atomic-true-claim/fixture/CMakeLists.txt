cmake_minimum_required(VERSION 3.20)
project(parallel_sum CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_compile_options(-Wall -Wextra -Wpedantic)

find_package(Threads REQUIRED)

enable_testing()
add_executable(test_parallel_sum tests/test_parallel_sum.cpp)
target_include_directories(test_parallel_sum PRIVATE include)
target_link_libraries(test_parallel_sum PRIVATE Threads::Threads)
add_test(NAME test_parallel_sum COMMAND test_parallel_sum)
