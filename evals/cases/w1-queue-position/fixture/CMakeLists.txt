cmake_minimum_required(VERSION 3.20)
project(itch_book CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_compile_options(-Wall -Wextra -Wpedantic)

add_library(book src/book.cpp)
target_include_directories(book PUBLIC include)

enable_testing()
add_executable(test_book tests/test_book.cpp)
target_link_libraries(test_book PRIVATE book)
add_test(NAME test_book COMMAND test_book)
