#include "atmsp/config.h"
#include <nlohmann/json.hpp>
#include <fstream>

namespace atmsp {

using nlohmann::json;

static int as_int(const json& j, const char* k, int def) {
    if (j.contains(k) && j[k].is_number_integer()) return j[k].get<int>();
    return def;
}
static bool as_bool(const json& j, const char* k, bool def) {
    if (j.contains(k) && j[k].is_boolean()) return j[k].get<bool>();
    return def;
}
static std::string as_str(const json& j, const char* k, const std::string& def) {
    if (j.contains(k) && j[k].is_string()) return j[k].get<std::string>();
    return def;
}

std::optional<AppConfig> load_config(const std::string& path) {
    std::ifstream f(path);
    if (!f.is_open()) return std::nullopt;
    json j; f >> j;

    AppConfig cfg;

    if (j.contains("logging") && j["logging"].is_object()) {
        auto L = j["logging"];
        cfg.logging.maskPan     = as_bool(L, "maskPan", true);
        cfg.logging.level       = as_str(L, "level", "info");
        cfg.logging.file        = as_str(L, "file", "logs/atmsp.log");
        cfg.logging.rotateMB    = as_int(L, "rotateMB", 5);
        cfg.logging.rotateFiles = as_int(L, "rotateFiles", 3);
    }

    if (j.contains("devices") && j["devices"].is_object()) {
        for (auto it = j["devices"].begin(); it != j["devices"].end(); ++it) {
            DeviceConfig dc;
            dc.type = as_str(it.value(), "type", "");
            if (it.value().contains("timeouts")) {
                const auto& T = it.value()["timeouts"];
                if (T.is_object()) {
                    dc.openMs    = as_int(T, "openMs", dc.openMs);
                    dc.executeMs = as_int(T, "executeMs", dc.executeMs);
                }
            }
            if (it.value().contains("features")) {
                const auto& F = it.value()["features"];
                if (F.is_object()) {
                    dc.emv           = as_bool(F, "emv", dc.emv);
                    dc.contactless   = as_bool(F, "contactless", dc.contactless);
                    dc.bypassAllowed = as_bool(F, "bypassAllowed", dc.bypassAllowed);
                }
            }
            cfg.devices.emplace(it.key(), dc);
        }
    }

    return cfg;
}

} // namespace atmsp
