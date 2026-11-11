cmake_minimum_required(VERSION 3.20)
project(trading_app CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_compile_options(-Wall -Wextra -Wpedantic)

find_package(Threads REQUIRED)

add_executable(trading_app
  src/main.cpp
  src/admin_server.cpp
  src/trading_loop.cpp)
target_link_libraries(trading_app PRIVATE Threads::Threads)
