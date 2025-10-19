cmake_minimum_required(VERSION 3.21)
project(atmsp LANGUAGES CXX VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(BUILD_TESTS "Build unit tests" ON)
option(USE_REAL_XFS "Build with real CEN/XFS headers and link against XFS Manager" OFF)

include(FetchContent)

# spdlog
FetchContent_Declare(
  spdlog
  GIT_REPOSITORY https://github.com/gabime/spdlog.git
  GIT_TAG v1.14.1
)
FetchContent_MakeAvailable(spdlog)

# nlohmann_json
FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.11.3
)
FetchContent_MakeAvailable(nlohmann_json)

add_library(atmsp
    src/logging.cpp
    src/session.cpp
    src/mock_card_reader.cpp
    src/mock_pin_pad.cpp
)
target_include_directories(atmsp PUBLIC include)
target_link_libraries(atmsp PUBLIC spdlog::spdlog_header_only nlohmann_json::nlohmann_json)

if (USE_REAL_XFS)
    target_compile_definitions(atmsp PUBLIC USE_REAL_XFS=1)
    # target_include_directories(atmsp PUBLIC "C:/XFS/Include")
    # target_link_libraries(atmsp PUBLIC xfs_64)
endif()

add_executable(atmsp_demo src/main.cpp)
target_link_libraries(atmsp_demo PRIVATE atmsp)

if (BUILD_TESTS)
  enable_testing()
  FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.14.0
  )
  FetchContent_MakeAvailable(googletest)
  add_executable(atmsp_tests
    tests/test_event_bus.cpp
    tests/test_session.cpp
    tests/test_mocks.cpp
  )
  target_link_libraries(atmsp_tests PRIVATE atmsp GTest::gtest_main)
  include(GoogleTest)
  gtest_discover_tests(atmsp_tests)
endif()
