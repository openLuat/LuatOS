
cmake_minimum_required(VERSION 2.8.12)

project("lwip" C)

set(LWIP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/lwip-2.1.2)

set (LWIP_DEFINITIONS LWIP_DEBUG=1)

if (${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
  add_subdirectory(${LWIP_DIR}/contrib/ports/win32/example_app)
  include_directories(${LWIP_DIR}/contrib/ports/win32/include)
elseif(${CMAKE_SYSTEM_NAME} STREQUAL "Linux" OR ${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  add_subdirectory(${LWIP_DIR}/contrib/ports/unix/example_app)
  include_directories(${LWIP_DIR}/contrib/ports/unix/include)
else()
  message(WARNING "Host ${CMAKE_SYSTEM_NAME} is not supported to build example_app")
endif()

include_directories(${LWIP_DIR}/src/include ${LWIP_DIR}/contrib/examples/example_app)

file(GLOB_RECURSE SOURCES binding/*.c)
add_library(lwip STATIC ${SOURCES})
