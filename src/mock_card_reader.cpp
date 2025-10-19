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
