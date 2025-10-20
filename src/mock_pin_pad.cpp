#include <thread>
#include <chrono>
#include <atomic>
#include <memory>
#include <nlohmann/json.hpp>

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
        // ---- Failure controls ----
        if (command == "InjectPinError") {
            next_pin_error_.store(true);
            std::promise<nlohmann::json> p;
            p.set_value(nlohmann::json{{"ok", true}});
            return p.get_future();
        }

        // ---- Normal commands ----
        if (command == "RequestPin") {
            // Publish a request event (so UI/upper layer can show prompt)
            if (bus_) {
                PinRequested req;
                req.minLen        = payload.value("minLen", 4);
                req.maxLen        = payload.value("maxLen", 12);
                req.bypassAllowed = payload.value("bypass", false);
                bus_->publish(req);
            }

            // If an error was injected, fail this request immediately
            if (next_pin_error_.exchange(false)) {
                std::promise<nlohmann::json> p;
                p.set_value(nlohmann::json{{"ok", false}, {"error", "KeypadFailure"}});
                return p.get_future();
            }

            // Happy path: return masked input asynchronously
            auto pr  = std::make_shared<std::promise<nlohmann::json>>();
            auto fut = pr->get_future();
            std::thread([this, pr]() {
                std::this_thread::sleep_for(1500ms);
                if (bus_) bus_->publish(PinEntered{ .masked = "****" });
                pr->set_value(nlohmann::json{{"ok", true}, {"masked", "****"}});
            }).detach();
            return fut;
        }

        // Unknown command
        std::promise<nlohmann::json> p;
        p.set_value(nlohmann::json{{"ok", false}, {"error", "UnknownCommand"}, {"command", command}});
        return p.get_future();
    }

    ~MockPinPad() override { close(); }

private:
    EventBus* bus_ {nullptr};
    std::string logical_;
    std::atomic<bool> opened_ {false};
    std::atomic<bool> next_pin_error_{false};
};

// Factory
std::unique_ptr<IPinPadSP> make_mock_pin_pad() {
    return std::make_unique<MockPinPad>();
}

} // namespace atmsp
