# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(MyApplication)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

option(NOTE_ENGINE_SIMULATOR_STUB "Build the x86_64 simulator stub runtime" OFF)

set(NOTE_ENGINE_BRIDGE_SOURCES
    napi_bridge.cpp)

if(NOTE_ENGINE_SIMULATOR_STUB)
    add_library(entry SHARED
        ${NOTE_ENGINE_BRIDGE_SOURCES}
        napi_runtime_simulator.cpp)
else()
    add_library(entry SHARED
        ${NOTE_ENGINE_BRIDGE_SOURCES}
        napi_init.cpp)
endif()

target_compile_features(entry PRIVATE cxx_std_17)

if(NOTE_ENGINE_SIMULATOR_STUB)
    target_link_libraries(entry PUBLIC
        libace_napi.z.so
        libhilog_ndk.z.so)
else()
    target_link_libraries(entry PUBLIC
        libace_napi.z.so
        libace_ndk.z.so
        libhilog_ndk.z.so
        libnative_window.so
        libEGL.so
        libGLESv3.so)
endif()
