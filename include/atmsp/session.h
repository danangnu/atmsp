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
