#include <gtest/gtest.h>
#include "atmsp/session.h"

using namespace atmsp;

TEST(Session, Lifecycle) {
    EventBus bus; int started=0, ended=0;
    auto id = bus.subscribe([&](const Event& e){
        std::visit([&](auto&& ev){
            using E = std::decay_t<decltype(ev)>;
            if constexpr (std::is_same_v<E, SessionStarted>) started++;
            if constexpr (std::is_same_v<E, SessionEnded>)   ended++;
        }, e);
    });
    Session s("ABC", bus);
    s.start();
    s.end();
    EXPECT_EQ(started, 1);
    EXPECT_EQ(ended, 1);
    bus.unsubscribe(id);
}
