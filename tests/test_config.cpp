#include <gtest/gtest.h>
#include "atmsp/config.h"
TEST(Config, LoadsBasic) {
  auto c = atmsp::load_config("config/devices.json");
  ASSERT_TRUE(c.has_value());
  EXPECT_TRUE(c->devices.contains("CARDREADER1"));
}
