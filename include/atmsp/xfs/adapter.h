#pragma once
#include <nlohmann/json.hpp>
#include <memory>
#include <string>
namespace atmsp { class EventBus; }
namespace atmsp::xfs {
class Adapter {
public:
  explicit Adapter(EventBus& bus): bus_(bus) {}
  bool startup(); bool cleanup();
  bool open(const std::string& logical); bool close(const std::string& logical);
  nlohmann::json execute(const std::string& cmd, const nlohmann::json& payload);
private: EventBus& bus_;
};
}
