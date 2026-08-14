cmake_minimum_required(VERSION 3.22.1)
project(sigsys_handler)

add_library(sigsys_handler SHARED sigsys_handler.c)
target_link_libraries(sigsys_handler log)
