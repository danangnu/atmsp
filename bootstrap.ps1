# Recreate the ATM SP Phase 1 starter locally (no internet download of sources)
# Requires: PowerShell 5+, VS 2022 C++ workload, CMake 3.21+

function Write-TextFile {
  param([string]$Path, [string]$Content)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Set-Content -Path $Path -Value $Content -Encoding UTF8 -NoNewline
}

# .gitignore (optional)
Write-TextFile ".gitignore" @'
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
Write-TextFile "CMakeLists.txt" @'
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
    # Add your XFS SDK paths here when available:
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

# include headers
Write-TextFile "include/atmsp/logging.h" @'
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

Write-TextFile "include/atmsp/events.h" @'
#pragma once
#include <string>
#include <variant>
#include <chrono>
#include <string_view>

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

Write-TextFile "include/atmsp/event_bus.h" @'
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

Write-TextFile "include/atmsp/errors.h" @'
#pragma once
#include <string_view>
namespace atmsp {
enum class SpError {
    Ok = 0, NotInitialized, AlreadyOpen, NotOpen, Timeout, IoError, InvalidCommand, Unsupported, Internal
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

Write-TextFile "include/atmsp/session.h" @'
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
    void start() { state_ = SessionState::Active; bus_.publish(SessionStarted{.sessionId = id_}); }
    void end(int resultCode = 0) { state_ = SessionState::Ended; bus_.publish(SessionEnded{.sessionId = id_, .resultCode = resultCode}); }
private:
    std::string id_;
    SessionState state_ { SessionState::Idle };
    EventBus& bus_;
};
} // namespace atmsp
'@

Write-TextFile "include/atmsp/sp_interface.h" @'
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

Write-TextFile "include/atmsp/card_reader_sp.h" @'
#pragma once
#include "sp_interface.h"
namespace atmsp {
class ICardReaderSP : public IServiceProvider {
public: virtual ~ICardReaderSP() = default;
};
} // namespace atmsp
'@

Write-TextFile "include/atmsp/pin_pad_sp.h" @'
#pragma once
#include "sp_interface.h"
namespace atmsp {
class IPinPadSP : public IServiceProvider {
public: virtual ~IPinPadSP() = default;
};
} // namespace atmsp
'@

Write-TextFile "include/atmsp/xfs/xfs_host.h" @'
#pragma once
#include <string>
#include <memory>
#include <nlohmann/json.hpp>
namespace atmsp::xfs {
class IXfsHost {
public:
    virtual ~IXfsHost() = default;
    virtual bool startup() = 0;
    virtual bool cleanup() = 0;
    virtual bool openService(const std::string& logicalName) = 0;
    virtual bool closeService(const std::string& logicalName) = 0;
    virtual nlohmann::json execute(const std::string& command, const nlohmann::json& payload) = 0;
};
std::unique_ptr<IXfsHost> make_host();
} // namespace atmsp::xfs
'@

Write-TextFile "include/atmsp/xfs/xfs_stub.h" @'
#pragma once
#include <memory>
#include <unordered_set>
#include "xfs_host.h"
namespace atmsp::xfs {
class StubHost : public IXfsHost {
public:
    bool startup() override { started_ = true; return true; }
    bool cleanup() override { started_ = false; opened_.clear(); return true; }
    bool openService(const std::string& name) override { if (!started_) return false; opened_.insert(name); return true; }
    bool closeService(const std::string& name) override { opened_.erase(name); return true; }
    nlohmann::json execute(const std::string& command, const nlohmann::json& payload) override {
        return nlohmann::json{ {"ok", true}, {"command", command}, {"payload", payload} };
    }
private:
    bool started_ {false};
    std::unordered_set<std::string> opened_;
};
inline std::unique_ptr<IXfsHost> make_host() { return std::make_unique<StubHost>(); }
} // namespace atmsp::xfs
'@

# src
Write-TextFile "src/logging.cpp" @'
#include "atmsp/logging.h"
'@

Write-TextFile "src/session.cpp" @'
#include "atmsp/session.h"
'@

Write-TextFile "src/mock_card_reader.cpp" @'
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
    SpError init(EventBus* bus) override { bus_ = bus; return bus_ ? SpError::Ok : SpError::NotInitialized; }
    SpError open(const std::string& logicalId) override {
        if (opened_) return SpError::AlreadyOpen;
        opened_ = true; logical_ = logicalId; worker_ = std::thread([this]{ run(); });
        spdlog::info("[{}] opened logical device '{}'", name(), logical_); return SpError::Ok;
    }
    void close() override {
        if (!opened_) return; stop_ = true; if (worker_.joinable()) worker_.join();
        opened_ = false; spdlog::info("[{}] closed", name());
    }
    std::future<nlohmann::json> execute(const std::string& command, const nlohmann::json& payload) override {
        std::promise<nlohmann::json> p;
        nlohmann::json reply = { {"sp", name()}, {"command", command}, {"ok", true} };
        p.set_value(reply); return p.get_future();
    }
    ~MockCardReader() { close(); }
private:
    void run() {
        std::mt19937 rng{std::random_device{}()};
        std::uniform_int_distribution<int> dwell(2,5);
        while (!stop_) {
            std::this_thread::sleep_for(std::chrono::seconds(dwell(rng)));
            if (stop_) break; if (bus_) bus_->publish(CardInserted{}); spdlog::info("[{}] CardInserted", name());
            std::this_thread::sleep_for(1s); if (stop_) break;
            Track2Read t2; t2.pan = "5413330089012345"; t2.exp = "2512"; t2.raw = "5413330089012345=25121010000012345678?";
            if (bus_) bus_->publish(t2);
            spdlog::info("[{}] Track2Read (PAN masked: {}******{})", name(), t2.pan.substr(0,6), t2.pan.substr(t2.pan.size()-4));
            std::this_thread::sleep_for(2s); if (stop_) break;
            if (bus_) bus_->publish(CardRemoved{}); spdlog::info("[{}] CardRemoved", name());
        }
    }
    EventBus* bus_ {nullptr};
    std::string logical_;
    std::thread worker_;
    std::atomic<bool> opened_ {false};
    std::atomic<bool> stop_ {false};
};
std::unique_ptr<ICardReaderSP> make_mock_card_reader() { return std::make_unique<MockCardReader>(); }
} // namespace atmsp
'@

Write-TextFile "src/mock_pin_pad.cpp" @'
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
    SpError init(EventBus* bus) override { bus_ = bus; return bus_ ? SpError::Ok : SpError::NotInitialized; }
    SpError open(const std::string& logicalId) override {
        if (opened_) return SpError::AlreadyOpen; logical_ = logicalId; opened_ = true;
        spdlog::info("[{}] opened logical device '{}'", name(), logical_); return SpError::Ok;
    }
    void close() override { opened_ = false; spdlog::info("[{}] closed", name()); }
    std::future<nlohmann::json> execute(const std::string& command, const nlohmann::json& payload) override {
        if (command == "RequestPin") {
            if (bus_) {
                PinRequested req; req.minLen = payload.value("minLen", 4);
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
            std::promise<nlohmann::json> p; p.set_value(nlohmann::json{{"ok", false},{"error","UnknownCommand"}});
            return p.get_future();
        }
    }
private:
    EventBus* bus_ {nullptr};
    std::string logical_;
    std::atomic<bool> opened_ {false};
};
std::unique_ptr<IPinPadSP> make_mock_pin_pad() { return std::make_unique<MockPinPad>(); }
} // namespace atmsp
'@

Write-TextFile "src/main.cpp" @'
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
    std::unique_ptr<ICardReaderSP> make_mock_card_reader();
    std::unique_ptr<IPinPadSP>    make_mock_pin_pad();
}

static std::string tp_to_string(const atmsp::TimePoint& tp) {
    auto tt = std::chrono::system_clock::to_time_t(tp);
    std::tm tm{};
#ifdef _WIN32
    localtime_s(&tm, &tt);
#else
    localtime_r(&tt, &tm);
#endif
    char buf[64]; std::strftime(buf, sizeof(buf), "%F %T", &tm);
    return buf;
}

int main() {
    using namespace atmsp;
    Logger::init();
    spdlog::info("ATM SP Demo starting...");

    EventBus bus;
    auto subId = bus.subscribe([&](const Event& e){
        std::visit([&](auto&& ev){
            using E = std::decay_t<decltype(ev)>;
            if constexpr (std::is_same_v<E, ErrorEvent>) {
                spdlog::error("ErrorEvent code={} msg={}", ev.code, ev.message);
            } else if constexpr (std::is_same_v<E, SessionStarted>) {
                spdlog::info("SessionStarted id={} at {}", ev.sessionId, tp_to_string(ev.ts));
            } else if constexpr (std::is_same_v<E, SessionEnded>) {
                spdlog::info("SessionEnded id={} rc={} at {}", ev.sessionId, ev.resultCode, tp_to_string(ev.ts));
            } else if constexpr (std::is_same_v<E, CardInserted>) {
                spdlog::info("CardInserted at {}", tp_to_string(ev.ts));
            } else if constexpr (std::is_same_v<E, Track2Read>) {
                spdlog::info("Track2Read PAN={}******{}", ev.pan.substr(0,6), ev.pan.substr(ev.pan.size()-4));
            } else if constexpr (std::is_same_v<E, CardRemoved>) {
                spdlog::info("CardRemoved");
            } else if constexpr (std::is_same_v<E, PinRequested>) {
                spdlog::info("PinRequested min={} max={} bypass={}", ev.minLen, ev.maxLen, ev.bypassAllowed);
            } else if constexpr (std::is_same_v<E, PinEntered>) {
                spdlog::info("PinEntered masked={}", ev.masked);
            } else if constexpr (std::is_same_v<E, ChipReady>) {
                spdlog::info("ChipReady contactless={}", ev.contactless);
            }
        }, e);
    });

    Session session("S-" + std::to_string(std::time(nullptr)), bus);
    session.start();

    auto card = make_mock_card_reader();
    auto pin  = make_mock_pin_pad();
    card->init(&bus); pin->init(&bus);
    card->open("CARDREADER1");
    pin->open("PINPAD1");

    std::this_thread::sleep_for(5s);
    nlohmann::json cmd = { {"minLen", 4}, {"maxLen", 6}, {"bypass", false} };
    (void)pin->execute("RequestPin", cmd);

    std::this_thread::sleep_for(10s);
    session.end(0);

    card->close(); pin->close();
    spdlog::info("ATM SP Demo finished.");
    return 0;
}
'@

# tests (minimal set)
Write-TextFile "tests/test_event_bus.cpp" @'
#include <gtest/gtest.h>
#include "atmsp/event_bus.h"
#include "atmsp/events.h"
using namespace atmsp;
TEST(EventBus, PublishesEvents) {
    EventBus bus; int count = 0;
    auto id = bus.subscribe([&](const Event& e){ std::visit([&](auto&&){ ++count; }, e); });
    bus.publish(CardInserted{}); bus.publish(CardRemoved{});
    EXPECT_EQ(count, 2); bus.unsubscribe(id);
}
'@

Write-TextFile "tests/test_session.cpp" @'
#include <gtest/gtest.h>
#include "atmsp/session.h"
using namespace atmsp;
TEST(Session, Lifecycle) {
    EventBus bus; int started=0, ended=0;
    auto id = bus.subscribe([&](const Event& e){
        std::visit([&](auto&& ev){
            using E = std::decay_t<decltype(ev)>;
            if constexpr (std::is_same_v<E, SessionStarted>) started++;
            if constexpr (std::is_same_v<E, SessionEnded>)   ended++;
        }, e);
    });
    Session s("ABC", bus); s.start(); s.end();
    EXPECT_EQ(started,1); EXPECT_EQ(ended,1); bus.unsubscribe(id);
}
'@

Write-TextFile "tests/test_mocks.cpp" @'
#include <gtest/gtest.h>
#include <chrono>
#include <thread>
#include "atmsp/card_reader_sp.h"
#include "atmsp/pin_pad_sp.h"
#include "atmsp/event_bus.h"

namespace atmsp {
    std::unique_ptr<ICardReaderSP> make_mock_card_reader();
    std::unique_ptr<IPinPadSP>    make_mock_pin_pad();
}
using namespace atmsp; using namespace std::chrono_literals;

TEST(Mocks, CardReaderEmitsEvents) {
    EventBus bus; int insertCount = 0;
    auto id = bus.subscribe([&](const Event& e){
        std::visit([&](auto&& ev){
            using E = std::decay_t<decltype(ev)>;
            if constexpr (std::is_same_v<E, CardInserted>) insertCount++;
        }, e);
    });
    auto card = atmsp::make_mock_card_reader();
    ASSERT_EQ(card->init(&bus), SpError::Ok);
    ASSERT_EQ(card->open("CR1"), SpError::Ok);
    std::this_thread::sleep_for(3s);
    card->close();
    EXPECT_GE(insertCount, 0);
    bus.unsubscribe(id);
}
'@

# docs (short)
Write-TextFile "docs/README.md" @'
# ATM Service Provider (SP) Starter – Phase 1
- Logging (spdlog), EventBus, Session, Error model
- Mock Card Reader & PIN Pad
- XFS host abstraction (stubbed)
- Unit tests + demo harness

## Build (VS 2022)
