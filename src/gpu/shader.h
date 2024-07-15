#ifndef VKAD_GPU_SHADER_H_
#define VKAD_GPU_SHADER_H_

#include "vulkan/vulkan_core.h"

namespace vkad {

enum class ShaderType {
   kVertex,
   kFragment,
};

class Shader {
public:
   Shader() : device_(VK_NULL_HANDLE), module_(VK_NULL_HANDLE) {}

   void init(VkDevice device, const char *file_path, ShaderType type);
   void deinit();

   VkPipelineShaderStageCreateInfo pipeline_stage() const;

private:
   VkDevice device_;
   VkShaderModule module_;
   ShaderType type_;
};

} // namespace vkad

#endif // !VKAD_GPU_SHADER_H_
