#pragma once

#include <vector>

#include "vulkan/vulkan_core.h"

#include "shader.h"

namespace vkad {

class Pipeline {
public:
   explicit Pipeline(
       VkDevice device, VkVertexInputBindingDescription vertex_binding,
       const std::vector<VkVertexInputAttributeDescription> &vertex_attributes,
       const Shader &vertex_shader, const Shader &fragment_shader,
       VkDescriptorSetLayout descriptor_layout, VkRenderPass render_pass
   );

   explicit inline Pipeline(Pipeline &&other) {
      layout_ = other.layout_;
      other.layout_ = VK_NULL_HANDLE;
      pipeline_ = other.pipeline_;
      other.pipeline_ = VK_NULL_HANDLE;
      device_ = other.device_;
   }

   Pipeline(const Pipeline &other) = delete;

   ~Pipeline();

   Pipeline &operator=(const Pipeline &other) = delete;

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
