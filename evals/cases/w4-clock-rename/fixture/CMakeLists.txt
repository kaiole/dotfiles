cmake_minimum_required(VERSION 3.20)
project(orderbook_bench CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()
add_compile_options(-Wall -Wextra -Wpedantic)

add_library(book INTERFACE)
target_include_directories(book INTERFACE include)

foreach(name bench_add bench_cancel bench_match)
  add_executable(${name} bench/${name}.cpp)
  target_link_libraries(${name} PRIVATE book)
endforeach()
