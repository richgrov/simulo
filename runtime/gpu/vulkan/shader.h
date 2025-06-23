#pragma once

#include <cstdint>
#include <span>
#include <vulkan/vulkan_core.h>

#include "device.h"

namespace simulo {

class Shader {
public:
   Shader(Device &device, std::span<const uint8_t> code);
   Shader(Shader &&other);
   Shader(const Shader &other) = delete;

   ~Shader();

   Shader &operator=(const Shader &other) = delete;

   VkShaderModule module() const {
      return module_;
   }

private:
   VkDevice device_;
   VkShaderModule module_;
};

} // namespace simulo
