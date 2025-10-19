#include <gtest/gtest.h>
#include "atmsp/event_bus.h"
#include "atmsp/events.h"

using namespace atmsp;

TEST(EventBus, PublishesEvents) {
    EventBus bus;
    int count = 0;
    auto id = bus.subscribe([&](const Event& e){
        std::visit([&](auto&&){ ++count; }, e);
    });
    bus.publish(CardInserted{});
    bus.publish(CardRemoved{});
    EXPECT_EQ(count, 2);
    bus.unsubscribe(id);
}
