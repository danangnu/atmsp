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
