#include <iostream>
#include <string>
#include <memory>
#include <thread>
#include <chrono>
#include <ctime>
#include <algorithm>            // std::clamp
#include <nlohmann/json.hpp>

#include "atmsp/logging.h"
#include "atmsp/event_bus.h"
#include "atmsp/session.h"
#include "atmsp/events.h"
#include "atmsp/card_reader_sp.h"
#include "atmsp/pin_pad_sp.h"
#include "atmsp/config.h"

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
    char buf[64];
    std::strftime(buf, sizeof(buf), "%F %T", &tm);
    return buf;
}

static void print_usage() {
    std::cout
      << "atmsp_demo usage:\n"
      << "  atmsp_demo [--config <path>|--config=<path>] [--fail-rate <0-100>|--fail-rate=NN] [--pin-error] [--help]\n"
      << "Options:\n"
      << "  --config       Path to devices.json (default: config/devices.json)\n"
      << "  --fail-rate    Percent chance (0..100) to drop Track2Read in MockCardReader\n"
      << "  --pin-error    Force the next RequestPin to fail with KeypadFailure\n"
      << "  --help         Show this help and exit\n";
}

int main(int argc, char** argv) {
    using namespace atmsp;

    // --- 0) Parse CLI flags (before loading config) ---
    std::string cfgPath = "config/devices.json";
    int failPct = -1;          // <0 means "not specified"
    bool injectPinErr = false;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--help" || a == "-h" || a == "/?") {
            print_usage();
            return 0;
        }
        else if (a == "--config" && (i + 1) < argc) {
            cfgPath = argv[++i];
        }
        else if (a.rfind("--config=", 0) == 0) {
            cfgPath = a.substr(std::string("--config=").size());
        }
        else if (a == "--fail-rate" && (i + 1) < argc) {
            try {
                failPct = std::stoi(argv[++i]);
                failPct = std::clamp(failPct, 0, 100);
            } catch (...) { failPct = 0; }
        }
        else if (a.rfind("--fail-rate=", 0) == 0) {
            try {
                failPct = std::stoi(a.substr(std::string("--fail-rate=").size()));
                failPct = std::clamp(failPct, 0, 100);
            } catch (...) { failPct = 0; }
        }
        else if (a == "--pin-error") {
            injectPinErr = true;
        }
        else {
            std::cerr << "Unknown argument: " << a << "\n";
            print_usage();
            return 2;
        }
    }

    // --- 1) Load config & initialize logging ---
    auto cfg = load_config(cfgPath);
    Logger::init();  // console + rotating file sinks

    if (!cfg) {
        spdlog::warn("Config not found or invalid at '{}'; using defaults.", cfgPath);
    } else {
        // Honor log level from config (optional)
        const auto& lvl = cfg->logging.level;
        if (lvl == "debug")      spdlog::set_level(spdlog::level::debug);
        else if (lvl == "info")  spdlog::set_level(spdlog::level::info);
        else if (lvl == "warn")  spdlog::set_level(spdlog::level::warn);
        else if (lvl == "error") spdlog::set_level(spdlog::level::err);
    }

    spdlog::info("ATM SP Demo starting... (config='{}', fail-rate={}, pin-error={})",
                 cfgPath, (failPct < 0 ? -1 : failPct), injectPinErr);

    // --- 2) Event bus & subscriber ---
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

    // --- 3) Start a session ---
    Session session("S-" + std::to_string(std::time(nullptr)), bus);
    session.start();

    // --- 4) Create and open mock devices ---
    std::string cardLogical = "CARDREADER1";
    std::string pinLogical  = "PINPAD1";
    if (cfg) {
        if (!cfg->devices.count(cardLogical))
            spdlog::warn("Device '{}' not found in config; using default.", cardLogical);
        if (!cfg->devices.count(pinLogical))
            spdlog::warn("Device '{}' not found in config; using default.", pinLogical);
    }

    auto card = make_mock_card_reader();
    auto pin  = make_mock_pin_pad();

    card->init(&bus);
    pin->init(&bus);
    card->open(cardLogical);
    pin->open(pinLogical);

    // --- 5) Apply CLI-driven failure injection (optional) ---
    if (failPct >= 0) {
        (void)card->execute("SetFailureRate", {{"pct", failPct}});
        spdlog::warn("[CLI] SetFailureRate={}%% applied", failPct);
    }
    if (injectPinErr) {
        (void)pin->execute("InjectPinError", {});
        spdlog::warn("[CLI] InjectPinError scheduled for next RequestPin");
    }

    // --- 6) Trigger a PIN entry after a short delay ---
    std::this_thread::sleep_for(5s);

    bool bypass = false;
    int  minLen = 4, maxLen = 6;
    if (cfg) {
        auto it = cfg->devices.find(pinLogical);
        if (it != cfg->devices.end()) {
            bypass = it->second.bypassAllowed;
        }
    }

    nlohmann::json cmd = { {"minLen", minLen}, {"maxLen", maxLen}, {"bypass", bypass} };
    (void)pin->execute("RequestPin", cmd);

    // --- 7) Let events flow, then end the session ---
    std::this_thread::sleep_for(10s);
    session.end(0);

    // --- 8) Cleanup ---
    card->close();
    pin->close();

    spdlog::info("ATM SP Demo finished.");
    return 0;
}