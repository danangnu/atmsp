#pragma once
#include <string>
inline std::string mask_pan(const std::string& pan){
  if (pan.size() <= 10) return "******";
  return pan.substr(0,6) + "******" + pan.substr(pan.size()-4);
}
