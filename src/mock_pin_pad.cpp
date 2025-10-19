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
