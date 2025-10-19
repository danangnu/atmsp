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
    card->init(&bus);
    pin->init(&bus);
    card->open("CARDREADER1");
    pin->open("PINPAD1");

    std::this_thread::sleep_for(5s);
    nlohmann::json cmd = { {"minLen", 4}, {"maxLen", 6}, {"bypass", false} };
    (void)pin->execute("RequestPin", cmd);

    std::this_thread::sleep_for(10s);
    session.end(0);

    card->close();
    pin->close();
    spdlog::info("ATM SP Demo finished.");
    return 0;
}
