#include "shader.h"

#include <format>
#include <fstream>
#include <stdexcept>
#include <vector>

#include "vulkan/vulkan_core.h"

using namespace villa;

void Shader::init(VkDevice device, const char *file_path, ShaderType type) {
   device_ = device;
   type_ = type;

   std::ifstream file(file_path, std::ios::ate | std::ios::binary);
   file.unsetf(std::ios::skipws);

   if (!file.is_open()) {
      throw std::runtime_error(std::format("couldn't open {}", file_path));
   }

   file.seekg(0, std::ios::end);
   std::vector<char> data(file.tellg());

   file.seekg(0, std::ios::beg);
   file.read(data.data(), data.size());

   VkShaderModuleCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
       .codeSize = data.size(),
       .pCode = reinterpret_cast<uint32_t *>(data.data()),
   };

   if (vkCreateShaderModule(device, &create_info, nullptr, &module_) != VK_SUCCESS) {
      throw std::runtime_error(std::format("couldn't compile shader type {}", 0));
   }
}

void Shader::deinit() {
   if (module_ != VK_NULL_HANDLE) {
      vkDestroyShaderModule(device_, module_, nullptr);
   }
}

VkPipelineShaderStageCreateInfo Shader::pipeline_stage() const {
   VkShaderStageFlagBits type;
   switch (type_) {
   case ShaderType::kVertex:
      type = VK_SHADER_STAGE_VERTEX_BIT;
      break;
   case ShaderType::kFragment:
      type = VK_SHADER_STAGE_FRAGMENT_BIT;
      break;
   }

   return {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = type,
       .module = module_,
       .pName = "main",
   };
}
