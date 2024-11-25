#include "renderer.h"

#include <stdexcept>
#include <vector>

#include <vulkan/vulkan_core.h>

#include "geometry/geometry.h"
#include "gpu/vulkan/buffer.h"
#include "gpu/vulkan/instance.h"
#include "gpu/vulkan/physical_device.h"
#include "gpu/vulkan/pipeline.h"
#include "gpu/vulkan/status.h"
#include "gpu/vulkan/swapchain.h"
#include "mesh.h"
#include "res/model.frag.h"
#include "res/model.vert.h"
#include "res/text.frag.h"
#include "res/text.vert.h"
#include "ui/ui.h"
#include "util/memory.h"

using namespace vkad;

Renderer::Renderer(
    Instance &vk_instance, VkSurfaceKHR surface, uint32_t initial_width, uint32_t initial_height
)
    : vk_instance_(vk_instance),
      physical_device_(vk_instance_, surface),
      device_(physical_device_),
      swapchain_(
          {physical_device_.graphics_queue(), physical_device_.present_queue()},
          physical_device_.handle(), device_.handle(), surface, initial_width, initial_height
      ),
      render_pass_(VK_NULL_HANDLE),
      meshes_(16),
      staging_buffer_(1024 * 1024 * 8, device_.handle(), physical_device_) {

   VkAttachmentDescription color_attachment = {
       .format = swapchain_.img_format(),
       .samples = VK_SAMPLE_COUNT_1_BIT,
       .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
       .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
       .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
       .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
       .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
       .finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
   };

   VkAttachmentReference color_attachment_ref = {
       .attachment = 0,
       .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
   };

   VkSubpassDescription subpass = {
       .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
       .colorAttachmentCount = 1,
       .pColorAttachments = &color_attachment_ref,
   };

   VkSubpassDependency subpass_dependency = {
       .srcSubpass = VK_SUBPASS_EXTERNAL,
       .dstSubpass = 0,
       .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
       .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
       .srcAccessMask = 0,
       .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
   };

   VkRenderPassCreateInfo render_create = {
       .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
       .attachmentCount = 1,
       .pAttachments = &color_attachment,
       .subpassCount = 1,
       .pSubpasses = &subpass,
       .dependencyCount = 1,
       .pDependencies = &subpass_dependency,
   };

   VKAD_VK(vkCreateRenderPass(device_.handle(), &render_create, nullptr, &render_pass_));

   create_framebuffers();

   VkSamplerCreateInfo sampler_create = {
       .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
       .magFilter = VK_FILTER_NEAREST,
       .minFilter = VK_FILTER_NEAREST,
       .mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR,
       .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
       .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
       .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
   };
   VKAD_VK(vkCreateSampler(device_.handle(), &sampler_create, nullptr, &sampler_));

   command_pool_.init(device_.handle(), physical_device_.graphics_queue());
   command_buffer_ = command_pool_.allocate();

   VkSemaphoreCreateInfo semaphore_create = {.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
   VkFenceCreateInfo fence_create = {
       .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT
   };

   if (vkCreateSemaphore(device_.handle(), &semaphore_create, nullptr, &sem_img_avail) !=
           VK_SUCCESS ||
       vkCreateSemaphore(device_.handle(), &semaphore_create, nullptr, &sem_render_complete) !=
           VK_SUCCESS ||
       vkCreateFence(device_.handle(), &fence_create, nullptr, &draw_cycle_complete) !=
           VK_SUCCESS) {
      throw std::runtime_error("failed to create semaphore(s)");
   }

   pipeline_ids_.ui = create_pipeline(
       sizeof(UiVertex),
       std::vector<VkVertexInputAttributeDescription>(
           UiVertex::kAttributes.begin(), UiVertex::kAttributes.end()
       ),
       {{std::span(shader_text_vert, shader_text_vert_len), false},
        {std::span(shader_text_frag, shader_text_frag_len), true}},
       {
           DescriptorPool::uniform_buffer_dynamic(0),
           DescriptorPool::combined_image_sampler(1),
       }
   );

   pipeline_ids_.mesh = create_pipeline(
       sizeof(ModelVertex),
       std::vector<VkVertexInputAttributeDescription>(
           ModelVertex::kAttributes.begin(), ModelVertex::kAttributes.end()
       ),
       {{std::span(shader_model_vert, shader_model_vert_len), false},
        {std::span(shader_model_frag, shader_model_frag_len), true}},
       {DescriptorPool::uniform_buffer_dynamic(0)}
   );
}

Renderer::~Renderer() {
   device_.wait_idle();

   for (const Material &mat : pipelines_) {
      vkDestroyDescriptorSetLayout(device_.handle(), mat.descriptor_set_layout, nullptr);
   }

   for (const auto &kv : shaders_) {
      vkDestroyShaderModule(device_.handle(), kv.second.module, nullptr);
   }

   vkDestroySemaphore(device_.handle(), sem_img_avail, nullptr);
   vkDestroySemaphore(device_.handle(), sem_render_complete, nullptr);
   vkDestroyFence(device_.handle(), draw_cycle_complete, nullptr);

   vkDestroySampler(device_.handle(), sampler_, nullptr);

   for (const VkFramebuffer framebuffer : framebuffers_) {
      vkDestroyFramebuffer(device_.handle(), framebuffer, nullptr);
   }

   command_pool_.deinit();

   if (render_pass_ != VK_NULL_HANDLE) {
      vkDestroyRenderPass(device_.handle(), render_pass_, nullptr);
   }
}

uint16_t Renderer::create_pipeline(
    uint32_t vertex_size, const std::vector<VkVertexInputAttributeDescription> &attrs,
    const std::vector<std::pair<std::span<unsigned char>, bool>> &data,
    const std::vector<VkDescriptorSetLayoutBinding> &bindings
) {
   VkVertexInputBindingDescription binding = {
       .binding = 0,
       .stride = vertex_size,
       .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
   };

   std::vector<Shader> shaders;
   for (const std::pair<std::span<unsigned char>, bool> &shader_info : data) {
      const std::span<unsigned char> &shader_data = shader_info.first;
      bool fragment = shader_info.second;
      ensure_shader_loaded(shader_data.data(), shader_data.size(), fragment);
      shaders.push_back(shaders_[shader_data.data()]);
   }

   VkDescriptorSetLayoutCreateInfo layout_create = {
       .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
       .bindingCount = static_cast<uint32_t>(bindings.size()),
       .pBindings = bindings.data(),
   };
   VkDescriptorSetLayout layout;
   VKAD_VK(vkCreateDescriptorSetLayout(device_.handle(), &layout_create, nullptr, &layout));

   std::vector<VkDescriptorPoolSize> sizes;
   sizes.reserve(bindings.size());
   for (const auto &binding : bindings) {
      sizes.push_back({
          .type = binding.descriptorType,
          .descriptorCount = binding.descriptorCount,
      });
   }

   pipelines_.emplace_back(Material{
       .descriptor_set_layout = layout,
       .pipeline = Pipeline(device_.handle(), binding, attrs, shaders, layout, render_pass_),
       .descriptor_pool = DescriptorPool(device_.handle(), layout, sizes, 1),
       .descriptor_set = VK_NULL_HANDLE,
   });
   return pipelines_.size() - 1;
}

void Renderer::ensure_shader_loaded(
    const unsigned char *data, size_t size, bool fragment_shader_temp
) {
   if (shaders_.contains(data)) {
      return;
   }

   Shader shader;
   shader.type = fragment_shader_temp ? VK_SHADER_STAGE_FRAGMENT_BIT : VK_SHADER_STAGE_VERTEX_BIT;
   /*if (!fragment_shader_temp) {
      shader.type = VK_SHADER_STAGE_VERTEX_BIT;
   } else if (path.find("frag") != std::string::npos) {
      shader.type = VK_SHADER_STAGE_FRAGMENT_BIT;
   } else {
      VKAD_PANIC("couldn't determine shader type of {}", path);
   }*/

   VkShaderModuleCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
       .codeSize = size,
       .pCode = reinterpret_cast<const uint32_t *>(data),
   };
   VKAD_VK(vkCreateShaderModule(device_.handle(), &create_info, nullptr, &shader.module));

   shaders_.insert({data, shader});
}

void Renderer::recreate_swapchain(uint32_t width, uint32_t height, VkSurfaceKHR surface) {
   swapchain_.dispose();
   swapchain_ = std::move(Swapchain(
       {physical_device_.graphics_queue(), physical_device_.present_queue()},
       physical_device_.handle(), device_.handle(), surface, width, height
   ));

   for (const VkFramebuffer framebuffer : framebuffers_) {
      vkDestroyFramebuffer(device_.handle(), framebuffer, nullptr);
   }

   create_framebuffers();
}

void Renderer::begin_preframe() {
   preframe_cmd_buf_ = command_pool_.allocate();

   VkCommandBufferBeginInfo begin_info = {
       .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
       .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
   };
   VKAD_VK(vkBeginCommandBuffer(preframe_cmd_buf_, &begin_info));
}

void Renderer::buffer_copy(const StagingBuffer &src, Buffer &dst) {
   VkBufferCopy copy_region = {
       .srcOffset = 0,
       .dstOffset = 0,
       .size = src.size(),
   };
   vkCmdCopyBuffer(preframe_cmd_buf_, src.buffer(), dst.buffer(), 1, &copy_region);
}

void Renderer::upload_texture(const StagingBuffer &src, Image &image) {
   VkBufferImageCopy region = {
       .imageSubresource =
           {
               .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
               .mipLevel = 0,
               .baseArrayLayer = 0,
               .layerCount = 1,
           },
       .imageExtent =
           {
               .width = static_cast<uint32_t>(image.width()),
               .height = static_cast<uint32_t>(image.height()),
               .depth = 1,
           },
   };

   vkCmdCopyBufferToImage(
       preframe_cmd_buf_, src.buffer(), image.handle(), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1,
       &region
   );
}

void Renderer::end_preframe() {
   vkEndCommandBuffer(preframe_cmd_buf_);

   VkSubmitInfo submit_info = {
       .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
       .commandBufferCount = 1,
       .pCommandBuffers = &preframe_cmd_buf_,
   };
   vkQueueSubmit(device_.graphics_queue(), 1, &submit_info, VK_NULL_HANDLE);
   vkQueueWaitIdle(device_.graphics_queue());
}

bool Renderer::begin_draw() {
   vkWaitForFences(device_.handle(), 1, &draw_cycle_complete, VK_TRUE, UINT64_MAX);

   VkResult next_image_res = vkAcquireNextImageKHR(
       device_.handle(), swapchain_.handle(), UINT64_MAX, sem_img_avail, VK_NULL_HANDLE,
       &current_framebuffer_
   );

   if (next_image_res == VK_ERROR_OUT_OF_DATE_KHR) {
      return false;
   }

   VKAD_VK(next_image_res);

   vkResetFences(device_.handle(), 1, &draw_cycle_complete);
   vkResetCommandBuffer(command_buffer_, 0);

   VkCommandBufferBeginInfo cmd_begin = {
       .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
   };
   VKAD_VK(vkBeginCommandBuffer(command_buffer_, &cmd_begin));

   VkClearValue clear_color = {.color = {0.4f, 0.4f, 0.4f, 1.0f}};
   VkRenderPassBeginInfo render_begin = {
       .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
       .renderPass = render_pass_,
       .framebuffer = framebuffers_[current_framebuffer_],
       .renderArea =
           {
               .extent = swapchain_.extent(),
           },
       .clearValueCount = 1,
       .pClearValues = &clear_color,
   };

   vkCmdBeginRenderPass(command_buffer_, &render_begin, VK_SUBPASS_CONTENTS_INLINE);
   return true;
}

void Renderer::set_material(int material_id) {
   Material &mat = pipelines_[material_id];
   vkCmdBindPipeline(command_buffer_, VK_PIPELINE_BIND_POINT_GRAPHICS, mat.pipeline.handle());

   VkViewport viewport = {
       .width = static_cast<float>(swapchain_.extent().width),
       .height = static_cast<float>(swapchain_.extent().height),
       .maxDepth = 1.0f,
   };
   vkCmdSetViewport(command_buffer_, 0, 1, &viewport);

   VkRect2D scissor = {
       .extent = swapchain_.extent(),
   };
   vkCmdSetScissor(command_buffer_, 0, 1, &scissor);
}

void Renderer::set_uniform(int material_id, uint32_t offset) {
   Material &mat = pipelines_[material_id];

   uint32_t offsets[] = {offset};
   vkCmdBindDescriptorSets(
       command_buffer_, VK_PIPELINE_BIND_POINT_GRAPHICS, mat.pipeline.layout(), 0, 1,
       &mat.descriptor_set, 1, offsets
   );
}

void Renderer::draw(int mesh_id) {
   VertexIndexBuffer &buffer = meshes_.get(mesh_id);

   VkBuffer buffers[] = {buffer.buffer()};
   VkDeviceSize offsets[] = {0};
   vkCmdBindVertexBuffers(command_buffer_, 0, 1, buffers, offsets);
   vkCmdBindIndexBuffer(
       command_buffer_, buffer.buffer(), buffer.index_offset(), VK_INDEX_TYPE_UINT16
   );

   vkCmdDrawIndexed(command_buffer_, buffer.num_indices(), 1, 0, 0, 0);
}

void Renderer::end_draw() {
   vkCmdEndRenderPass(command_buffer_);
   VKAD_VK(vkEndCommandBuffer(command_buffer_));

   VkPipelineStageFlags wait_stages[] = {VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
   VkSubmitInfo submit_info = {
       .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
       .waitSemaphoreCount = 1,
       .pWaitSemaphores = &sem_img_avail,
       .pWaitDstStageMask = wait_stages,
       .commandBufferCount = 1,
       .pCommandBuffers = &command_buffer_,
       .signalSemaphoreCount = 1,
       .pSignalSemaphores = &sem_render_complete,
   };
   VKAD_VK(vkQueueSubmit(device_.graphics_queue(), 1, &submit_info, draw_cycle_complete));

   VkSwapchainKHR swap_chains[] = {swapchain_.handle()};
   VkPresentInfoKHR present_info = {
       .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
       .waitSemaphoreCount = 1,
       .pWaitSemaphores = &sem_render_complete,
       .swapchainCount = VKAD_ARRAY_LEN(swap_chains),
       .pSwapchains = swap_chains,
       .pImageIndices = &current_framebuffer_,
   };
   vkQueuePresentKHR(device_.present_queue(), &present_info);
}

void Renderer::create_framebuffers() {
   framebuffers_.resize(swapchain_.num_images());
   for (int i = 0; i < swapchain_.num_images(); ++i) {
      VkImageView attachments[] = {swapchain_.image_view(i)};

      VkExtent2D extent = swapchain_.extent();
      VkFramebufferCreateInfo create_info = {
          .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
          .renderPass = render_pass_,
          .attachmentCount = VKAD_ARRAY_LEN(attachments),
          .pAttachments = attachments,
          .width = extent.width,
          .height = extent.height,
          .layers = 1,
      };
      VKAD_VK(vkCreateFramebuffer(device_.handle(), &create_info, nullptr, &framebuffers_[i]));
   }
}
