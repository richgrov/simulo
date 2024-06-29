#ifndef VILLA_GPU_PIPELINE_H_
#define VILLA_GPU_PIPELINE_H_

#include <functional>
#include <vector>

#include "vulkan/vulkan_core.h"

#include "shader.h"
#include "swapchain.h"

namespace villa {

class Pipeline {
public:
   Pipeline()
       : render_pass_(VK_NULL_HANDLE), layout_(VK_NULL_HANDLE), pipeline_(VK_NULL_HANDLE),
         device_(VK_NULL_HANDLE) {}

   void init(
       VkDevice device, const std::vector<std::reference_wrapper<Shader>> &shaders,
       const Swapchain &swapchain
   );

   void deinit();

private:
   VkRenderPass render_pass_;
   VkPipelineLayout layout_;
   VkPipeline pipeline_;
   VkDevice device_;
};

} // namespace villa

#endif // !VILLA_GPU_PIPELINE_H_
