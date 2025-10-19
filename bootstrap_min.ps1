# Minimal, safe bootstrap for the ATM SP starter.
# Uses single-quoted here-strings @' ... '@ only.
# NOTE: Every closing '@ must be at column 1 (no spaces).

function New-FileUtf8 {
  param([string]$Path, [string]$Content)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

# .gitignore
New-FileUtf8 ".gitignore" @'
/build/
/out/
/dist/
CMakeFiles/
CMakeCache.txt
*.obj
*.o
*.pdb
*.exe
*.dll
*.lib
*.exp
*.ilk
*.log
*.user
*.VC.db
*.DS_Store
*.ipch
.vscode/
.idea/
'@

# CMakeLists.txt
New-FileUtf8 "CMakeLists.txt" @'
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
'@

# ===== include/atmsp =====

New-FileUtf8 "include/atmsp/logging.h" @'
#pragma once
#include <memory>
#include <string>
#include <vector>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/sinks/rotating_file_sink.h>

namespace atmsp {
class Logger {
public:
    static void init(const std::string& log_dir = "logs",
                     const std::string& file_name = "atmsp.log",
                     size_t max_size_bytes = 5 * 1024 * 1024,
                     size_t max_files = 3) {
        try {
            auto console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
            console_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %v");
            auto rotating_sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
                log_dir + "/" + file_name, max_size_bytes, max_files);
            rotating_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%t] [%^%l%$] %v");
            std::vector<spdlog::sink_ptr> sinks { console_sink, rotating_sink };
            auto logger = std::make_shared<spdlog::logger>("atmsp", begin(sinks), end(sinks));
            logger->set_level(spdlog::level::info);
            logger->flush_on(spdlog::level::info);
            spdlog::set_default_logger(logger);
        } catch (const spdlog::spdlog_ex& ex) {
            spdlog::set_level(spdlog::level::info);
            spdlog::warn("Logger initialization failed: {}", ex.what());
        }
    }
};
} // namespace atmsp
'@

New-FileUtf8 "include/atmsp/events.h" @'
#pragma once
#include <string>
#include <variant>
#include <chrono>

namespace atmsp {

using Clock = std::chrono::system_clock;
using TimePoint = std::chrono::time_point<Clock>;

struct BaseEvent { TimePoint ts { Clock::now() }; };
struct ErrorEvent : BaseEvent { int code {0}; std::string message; };

struct CardInserted : BaseEvent { };
struct CardRemoved  : BaseEvent { };
struct Track2Read   : BaseEvent { std::string pan; std::string exp; std::string raw; };
struct ChipReady    : BaseEvent { bool contactless{false}; };

struct PinRequested : BaseEvent { int minLen{4}; int maxLen{12}; bool bypassAllowed{false}; };
struct PinEntered   : BaseEvent { std::string masked; };

struct SessionStarted : BaseEvent { std::string sessionId; };
struct SessionEnded   : BaseEvent { std::string sessionId; int resultCode{0}; };

using Event = std::variant<ErrorEvent,
                           CardInserted, CardRemoved, Track2Read, ChipReady,
                           PinRequested, PinEntered,
                           SessionStarted, SessionEnded>;

} // namespace atmsp
'@

New-FileUtf8 "include/atmsp/event_bus.h" @'
#pragma once
#include <functional>
#include <mutex>
#include <vector>
#include <atomic>
#include <algorithm>
#include "events.h"

namespace atmsp {

class EventBus {
public:
    using HandlerId = std::size_t;
    using Handler = std::function<void(const Event&)>;

    HandlerId subscribe(Handler h) {
        std::lock_guard<std::mutex> lk(mu_);
        handlers_.push_back({++next_id_, std::move(h)});
        return next_id_;
    }

    void unsubscribe(HandlerId id) {
        std::lock_guard<std::mutex> lk(mu_);
        handlers_.erase(std::remove_if(handlers_.begin(), handlers_.end(),
            [&](auto& p){ return p.first == id; }), handlers_.end());
    }

    void publish(const Event& e) const {
        std::vector<Handler> snapshot;
        {
            std::lock_guard<std::mutex> lk(mu_);
            snapshot.reserve(handlers_.size());
            for (auto& [_, h] : handlers_) snapshot.push_back(h);
        }
        for (auto& h : snapshot) h(e);
    }

private:
    mutable std::mutex mu_;
    std::vector<std::pair<HandlerId, Handler>> handlers_;
    std::atomic<HandlerId> next_id_ {0};
};

} // namespace atmsp
'@

New-FileUtf8 "include/atmsp/errors.h" @'
#pragma once
#include <string_view>

namespace atmsp {
enum class SpError {
    Ok = 0,
    NotInitialized,
    AlreadyOpen,
    NotOpen,
    Timeout,
    IoError,
    InvalidCommand,
    Unsupported,
    Internal
};
inline std::string_view to_string(SpError e) {
    switch (e) {
        case SpError::Ok: return "Ok";
        case SpError::NotInitialized: return "NotInitialized";
        case SpError::AlreadyOpen: return "AlreadyOpen";
        case SpError::NotOpen: return "NotOpen";
        case SpError::Timeout: return "Timeout";
        case SpError::IoError: return "IoError";
        case SpError::InvalidCommand: return "InvalidCommand";
        case SpError::Unsupported: return "Unsupported";
        case SpError::Internal: return "Internal";
    }
    return "Unknown";
}
} // namespace atmsp
'@

New-FileUtf8 "include/atmsp/session.h" @'
#pragma once
#include <string>
#include <nlohmann/json.hpp>
#include "event_bus.h"
#include "events.h"

namespace atmsp {

enum class SessionState { Idle, Active, Ended };

class Session {
public:
    Session(std::string id, EventBus& bus) : id_(std::move(id)), bus_(bus) {}
    const std::string& id() const { return id_; }
    SessionState state() const { return state_; }

    void start() {
        state_ = SessionState::Active;
        bus_.publish(SessionStarted{.sessionId = id_});
    }

    void end(int resultCode = 0) {
        state_ = SessionState::Ended;
        bus_.publish(SessionEnded{.sessionId = id_, .resultCode = resultCode});
    }

private:
    std::string id_;
    SessionState state_ { SessionState::Idle };
    EventBus& bus_;
};

} // namespace atmsp
'@

New-FileUtf8 "include/atmsp/sp_interface.h" @'
#pragma once
#include <string>
#include <future>
#include <nlohmann/json.hpp>
#include "errors.h"
#include "event_bus.h"

namespace atmsp {

class IServiceProvider {
public:
    virtual ~IServiceProvider() = default;
    virtual std::string name() const = 0;
    virtual SpError init(EventBus* bus) = 0;
    virtual SpError open(const std::string& logicalId) = 0;
    virtual void close() = 0;
    virtual std::future<nlohmann::json> execute(const std::string& command,
                                                const nlohmann::json& payload) = 0;
};

} // namespace atmsp
'@

# ===== src =====

New-FileUtf8 "src/logging.cpp" @'
#include "atmsp/logging.h"
'@

New-FileUtf8 "src/session.cpp" @'
#include "atmsp/session.h"
'@

New-FileUtf8 "src/mock_card_reader.cpp" @'
#include <thread>
#include <chrono>
#include <random>
#include <atomic>
#include "atmsp/card_reader_sp.h"
#include "atmsp/events.h"
#include "atmsp/logging.h"

using namespace std::chrono_literals;

namespace atmsp {

class MockCardReader final : public ICardReaderSP {
public:
    std::string name() const override { return "MockCardReader"; }

    SpError init(EventBus* bus) override {
        bus_ = bus;
        return bus_ ? SpError::Ok : SpError::NotInitialized;
    }

    SpError open(const std::string& logicalId) override {
        if (opened_) return SpError::AlreadyOpen;
        opened_ = true;
        logical_ = logicalId;
        worker_ = std::thread([this]{ run(); });
        spdlog::info("[{}] opened logical device '{}'", name(), logical_);
        return SpError::Ok;
    }

    void close() override {
        if (!opened_) return;
        stop_ = true;
        if (worker_.joinable()) worker_.join();
        opened_ = false;
        spdlog::info("[{}] closed", name());
    }

    std::future<nlohmann::json> execute(const std::string& command,
                                        const nlohmann::json& payload) override {
        std::promise<nlohmann::json> p;
        nlohmann::json reply = {
            {"sp", name()},
            {"command", command},
            {"ok", true}
        };
        p.set_value(reply);
        return p.get_future();
    }

    ~MockCardReader() { close(); }

private:
    void run() {
        std::mt19937 rng{std::random_device{}()};
        std::uniform_int_distribution<int> dwell(2, 5);

        while (!stop_) {
            std::this_thread::sleep_for(std::chrono::seconds(dwell(rng)));
            if (stop_) break;
            if (bus_) bus_->publish(CardInserted{});
            spdlog::info("[{}] CardInserted", name());

            std::this_thread::sleep_for(1s);
            if (stop_) break;
            Track2Read t2;
            t2.pan = "5413330089012345";
            t2.exp = "2512";
            t2.raw = "5413330089012345=25121010000012345678?";
            if (bus_) bus_->publish(t2);
            spdlog::info("[{}] Track2Read (PAN masked: {}******{})",
                         name(), t2.pan.substr(0,6), t2.pan.substr(t2.pan.size()-4));

            std::this_thread::sleep_for(2s);
            if (stop_) break;
            if (bus_) bus_->publish(CardRemoved{});
            spdlog::info("[{}] CardRemoved", name());
        }
    }

    EventBus* bus_ {nullptr};
    std::string logical_;
    std::thread worker_;
    std::atomic<bool> opened_ {false};
    std::atomic<bool> stop_ {false};
};

std::unique_ptr<ICardReaderSP> make_mock_card_reader() {
    return std::make_unique<MockCardReader>();
}

} // namespace atmsp
'@

New-FileUtf8 "src/mock_pin_pad.cpp" @'
#include <thread>
#include <chrono>
#include <atomic>
#include "atmsp/pin_pad_sp.h"
#include "atmsp/events.h"
#include "atmsp/logging.h"

using namespace std::chrono_literals;

namespace atmsp {

class MockPinPad final : public IPinPadSP {
public:
    std::string name() const override { return "MockPinPad"; }

    SpError init(EventBus* bus) override {
        bus_ = bus;
        return bus_ ? SpError::Ok : SpError::NotInitialized;
    }

    SpError open(const std::string& logicalId) override {
        if (opened_) return SpError::AlreadyOpen;
        logical_ = logicalId;
        opened_ = true;
        spdlog::info("[{}] opened logical device '{}'", name(), logical_);
        return SpError::Ok;
    }

    void close() override {
        opened_ = false;
        spdlog::info("[{}] closed", name());
    }

    std::future<nlohmann::json> execute(const std::string& command,
                                        const nlohmann::json& payload) override {
        if (command == "RequestPin") {
            if (bus_) {
                PinRequested req;
                req.minLen = payload.value("minLen", 4);
                req.maxLen = payload.value("maxLen", 12);
                req.bypassAllowed = payload.value("bypass", false);
                bus_->publish(req);
            }
            auto pr = std::make_shared<std::promise<nlohmann::json>>();
            auto fut = pr->get_future();
            std::thread([this, pr](){
                std::this_thread::sleep_for(1500ms);
                if (bus_) bus_->publish(PinEntered{ .masked = "****" });
                pr->set_value(nlohmann::json{{"ok", true},{"masked","****"}});
            }).detach();
            return fut;
        } else {
            std::promise<nlohmann::json> p;
            p.set_value(nlohmann::json{{"ok", false},{"error","UnknownCommand"}});
            return p.get_future();
        }
    }

private:
    EventBus* bus_ {nullptr};
    std::string logical_;
    std::atomic<bool> opened_ {false};
};

std::unique_ptr<IPinPadSP> make_mock_pin_pad() {
    return std::make_unique<MockPinPad>();
}

} // namespace atmsp
'@

New-FileUtf8 "src/main.cpp" @'
#include <iostream>
#include <string>
#include <memory>
#include <thread>
#include <chrono>
#include <nlohmann/json.hpp>
#include "atmsp/logging.h"
#include "atmsp/event_bus.h"
#include "atmsp/session.h"
#include "atmsp/events.h"
#include "atmsp/card_reader_sp.h"
#include "atmsp/pin_pad_sp.h"

using namespace std::chrono_literals;

namespace atmsp {
    std::unique_ptr<ICardReaderSP> make_mock
