#include "shader.h"
#include "status.h"

#include <vulkan/vulkan_core.h>

using namespace simulo;

Shader::Shader(Device &device, std::span<uint8_t> code) : device_(device.handle()) {
   VkShaderModuleCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
       .codeSize = code.size(),
       .pCode = reinterpret_cast<const uint32_t *>(code.data()),
   };
   VKAD_VK(vkCreateShaderModule(device.handle(), &create_info, nullptr, &module_));
}

Shader::Shader(Shader &&other) : device_(other.device_), module_(other.module_) {
   other.device_ = nullptr;
   other.module_ = nullptr;
}

Shader::~Shader() {
   if (module_ != nullptr) {
      vkDestroyShaderModule(device_, module_, nullptr);
   }
}
