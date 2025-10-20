#pragma once
#include <string>
#include <unordered_map>
#include <optional>

namespace atmsp {

struct DeviceConfig {
    std::string type;           // "card_reader", "pin_pad", etc.
    int openMs{5000};
    int executeMs{10000};
    bool emv{false};
    bool contactless{false};
    bool bypassAllowed{false};
};

struct LoggingConfig {
    bool maskPan{true};
    std::string level{"info"};
    std::string file{"logs/atmsp.log"};
    int rotateMB{5};
    int rotateFiles{3};
};

struct AppConfig {
    LoggingConfig logging;
    std::unordered_map<std::string, DeviceConfig> devices;
};

// Loads config from path (default: "config/devices.json"). Returns std::nullopt on failure.
std::optional<AppConfig> load_config(const std::string& path);

} // namespace atmsp
