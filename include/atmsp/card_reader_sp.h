#pragma once
#include "sp_interface.h"
namespace atmsp {
class ICardReaderSP : public IServiceProvider {
public: virtual ~ICardReaderSP() = default;
};
} // namespace atmsp
