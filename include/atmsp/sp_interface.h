#pragma once
#include <string>
#include <future>
#include <nlohmann/json.hpp>
#include "errors.h"
#include "event_bus.h"

namespace atmsp {

class IServiceProvider {
public:
    virtual ~IServiceProvider() = default;
    virtual std::string name() const = 0;
    virtual SpError init(EventBus* bus) = 0;
    virtual SpError open(const std::string& logicalId) = 0;
    virtual void close() = 0;
    virtual std::future<nlohmann::json> execute(const std::string& command,
                                                const nlohmann::json& payload) = 0;
};

} // namespace atmsp
