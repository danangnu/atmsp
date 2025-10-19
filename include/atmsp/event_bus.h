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
