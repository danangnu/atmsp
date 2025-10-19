#pragma once
#include <memory>
#include <string>
#include <vector>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/sinks/rotating_file_sink.h>

namespace atmsp {
class Logger {
public:
    static void init(const std::string& log_dir = "logs",
                     const std::string& file_name = "atmsp.log",
                     size_t max_size_bytes = 5 * 1024 * 1024,
                     size_t max_files = 3) {
        try {
            auto console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
            console_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %v");
            auto rotating_sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
                log_dir + "/" + file_name, max_size_bytes, max_files);
            rotating_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%t] [%^%l%$] %v");
            std::vector<spdlog::sink_ptr> sinks { console_sink, rotating_sink };
            auto logger = std::make_shared<spdlog::logger>("atmsp", begin(sinks), end(sinks));
            logger->set_level(spdlog::level::info);
            logger->flush_on(spdlog::level::info);
            spdlog::set_default_logger(logger);
        } catch (const spdlog::spdlog_ex& ex) {
            spdlog::set_level(spdlog::level::info);
            spdlog::warn("Logger initialization failed: {}", ex.what());
        }
    }
};
} // namespace atmsp
