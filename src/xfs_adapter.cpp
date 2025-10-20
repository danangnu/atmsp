#include "atmsp/xfs/adapter.h"
#include "atmsp/event_bus.h"
#include "atmsp/events.h"
#include "atmsp/logging.h"

namespace atmsp::xfs {

bool Adapter::startup() {
  spdlog::info("[XFS] startup (stub)");
  return true;
}
bool Adapter::cleanup() {
  spdlog::info("[XFS] cleanup (stub)");
  return true;
}
bool Adapter::open(const std::string& logical) {
  spdlog::info("[XFS] open '{}' (stub)", logical);
  // Example: bus_.publish(SessionStarted{.sessionId="XFS-"+logical});
  return true;
}
bool Adapter::close(const std::string& logical) {
  spdlog::info("[XFS] close '{}' (stub)", logical);
  return true;
}
nlohmann::json Adapter::execute(const std::string& cmd, const nlohmann::json& payload) {
  spdlog::info("[XFS] exec cmd='{}' payload={}", cmd, payload.dump());
  return {{"ok", true}, {"cmd", cmd}};
}

} // namespace atmsp::xfs
