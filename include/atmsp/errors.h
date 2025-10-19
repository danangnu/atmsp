#pragma once
#include <string_view>

namespace atmsp {
enum class SpError {
    Ok = 0,
    NotInitialized,
    AlreadyOpen,
    NotOpen,
    Timeout,
    IoError,
    InvalidCommand,
    Unsupported,
    Internal
};
inline std::string_view to_string(SpError e) {
    switch (e) {
        case SpError::Ok: return "Ok";
        case SpError::NotInitialized: return "NotInitialized";
        case SpError::AlreadyOpen: return "AlreadyOpen";
        case SpError::NotOpen: return "NotOpen";
        case SpError::Timeout: return "Timeout";
        case SpError::IoError: return "IoError";
        case SpError::InvalidCommand: return "InvalidCommand";
        case SpError::Unsupported: return "Unsupported";
        case SpError::Internal: return "Internal";
    }
    return "Unknown";
}
} // namespace atmsp
