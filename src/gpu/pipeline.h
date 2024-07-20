#ifndef VKAD_GPU_PIPELINE_H_
#define VKAD_GPU_PIPELINE_H_

#include <vector>

#include "vulkan/vulkan_core.h"

namespace vkad {

struct Shader {
   VkShaderModule module;
   VkShaderStageFlagBits type;
};

class Pipeline {
public:
   Pipeline(
       VkDevice device, VkVertexInputBindingDescription vertex_binding,
       const std::vector<VkVertexInputAttributeDescription> &vertex_attributes,
       const std::vector<Shader> &shaders, VkDescriptorSetLayout descriptor_layout,
       VkRenderPass render_pass
   );

   ~Pipeline();

   inline VkPipeline handle() const {
      return pipeline_;
   }

   inline VkPipelineLayout layout() const {
      return layout_;
   }

private:
   VkPipelineLayout layout_;
   VkPipeline pipeline_;
   VkDevice device_;
};

} // namespace vkad

#endif // !VKAD_GPU_PIPELINE_H_
