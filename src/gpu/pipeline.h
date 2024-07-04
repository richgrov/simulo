#ifndef VILLA_GPU_PIPELINE_H_
#define VILLA_GPU_PIPELINE_H_

#include <functional>
#include <vector>

#include "vulkan/vulkan_core.h"

#include "shader.h"

namespace villa {

class Pipeline {
public:
   Pipeline(
       VkDevice device, VkVertexInputBindingDescription vertex_binding,
       const std::vector<VkVertexInputAttributeDescription> &vertex_attributes,
       const std::vector<std::reference_wrapper<Shader>> &shaders, VkRenderPass render_pass
   );

   ~Pipeline();

   inline VkPipeline handle() const {
      return pipeline_;
   }

   inline VkDescriptorSetLayout descriptor_set_layout() const {
      return descriptor_layout_;
   }

private:
   VkPipelineLayout layout_;
   VkDescriptorSetLayout descriptor_layout_;
   VkPipeline pipeline_;
   VkDevice device_;
};

} // namespace villa

#endif // !VILLA_GPU_PIPELINE_H_
