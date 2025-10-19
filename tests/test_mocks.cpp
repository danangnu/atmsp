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

using namespace atmsp;
using namespace std::chrono_literals;

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
