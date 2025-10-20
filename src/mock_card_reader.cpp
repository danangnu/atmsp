#include <thread>
#include <chrono>
#include <random>
#include <atomic>
#include <algorithm>          // std::clamp
#include <nlohmann/json.hpp>

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
        stop_ = false;
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
        // Failure injection: SetFailureRate { "pct": 0..100 }
        if (command == "SetFailureRate") {
            int pct = payload.value("pct", 0);
            pct = std::clamp(pct, 0, 100);
            fail_rate_pct_.store(pct);
            std::promise<nlohmann::json> p;
            p.set_value(nlohmann::json{{"ok", true}, {"pct", pct}});
            return p.get_future();
        }

        // (Optional) Read back the current failure rate
        if (command == "GetFailureRate") {
            std::promise<nlohmann::json> p;
            p.set_value(nlohmann::json{{"ok", true}, {"pct", fail_rate_pct_.load()}});
            return p.get_future();
        }

        // Default no-op command reply
        std::promise<nlohmann::json> p;
        p.set_value(nlohmann::json{
            {"sp", name()},
            {"command", command},
            {"ok", true}
        });
        return p.get_future();
    }

    ~MockCardReader() override { close(); }

private:
    void run() {
        std::mt19937 rng{std::random_device{}()};
        std::uniform_int_distribution<int> dwell_seconds(2, 5);
        std::uniform_int_distribution<int> r100(1, 100);

        while (!stop_) {
            // Simulate user inserting a card after some dwell time
            std::this_thread::sleep_for(std::chrono::seconds(dwell_seconds(rng)));
            if (stop_) break;

            if (bus_) bus_->publish(CardInserted{});
            spdlog::info("[{}] CardInserted", name());

            // Small delay before reading tracks
            std::this_thread::sleep_for(1s);
            if (stop_) break;

            // Prepare a fake track-2 read (masked in logs)
            Track2Read t2;
            t2.pan = "5413330089012345";
            t2.exp = "2512";
            t2.raw = "5413330089012345=25121010000012345678?";

            // Failure injection: drop Track2Read based on percentage
            const int dropChance = fail_rate_pct_.load();
            if (r100(rng) <= dropChance) {
                spdlog::warn("[{}] Simulated failure: dropped Track2Read", name());
            } else {
                if (bus_) bus_->publish(t2);
                spdlog::info("[{}] Track2Read (PAN masked: {}******{})",
                             name(), t2.pan.substr(0,6), t2.pan.substr(t2.pan.size()-4));
            }

            // A little time before the card is removed
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
    std::atomic<int>  fail_rate_pct_{0};   // 0..100% chance to drop Track2Read
};

// Factory (declared in headers used by the rest of the app)
std::unique_ptr<ICardReaderSP> make_mock_card_reader() {
    return std::make_unique<MockCardReader>();
}

} // namespace atmsp