#include "game.h"

#include <format>
#include <stdexcept>
#include <vector>

#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/instance.h"
#include "gpu/physical_device.h"
#include "gpu/pipeline.h"
#include "gpu/shader.h"
#include "gpu/swapchain.h"
#include "util/memory.h"

using namespace villa;

Game::Game(const char *title)
    : window_(title), vk_instance_(window_.vulkan_extensions()),
      surface_(window_.create_surface(vk_instance_.handle())),
      physical_device_(vk_instance_, surface_), device_(physical_device_),
      render_pass_(VK_NULL_HANDLE), was_left_clicking_(false), last_frame_time_(Clock::now()),
      delta_(0), last_width_(window_.width()), last_height_(window_.height()) {

   int width = window_.width();
   int height = window_.height();

   swapchain_.init(
       {physical_device_.graphics_queue(), physical_device_.present_queue()},
       physical_device_.handle(), device_.handle(), surface_, width, height
   );

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

   if (vkCreateRenderPass(device_.handle(), &render_create, nullptr, &render_pass_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create render pass");
   }

   vertex_shader_.init(device_.handle(), "shader-vert.spv", ShaderType::kVertex);
   fragment_shader_.init(device_.handle(), "shader-frag.spv", ShaderType::kFragment);

   create_framebuffers();

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
}

Game::~Game() {
   device_.wait_idle();

   vkDestroySemaphore(device_.handle(), sem_img_avail, nullptr);
   vkDestroySemaphore(device_.handle(), sem_render_complete, nullptr);
   vkDestroyFence(device_.handle(), draw_cycle_complete, nullptr);

   for (const VkFramebuffer framebuffer : framebuffers_) {
      vkDestroyFramebuffer(device_.handle(), framebuffer, nullptr);
   }

   command_pool_.deinit();

   vertex_shader_.deinit();
   fragment_shader_.deinit();

   if (render_pass_ != VK_NULL_HANDLE) {
      vkDestroyRenderPass(device_.handle(), render_pass_, nullptr);
   }

   swapchain_.deinit();

   if (surface_ != VK_NULL_HANDLE) {
      vkDestroySurfaceKHR(vk_instance_.handle(), surface_, nullptr);
   }
}

void Game::handle_resize(VkSurfaceKHR surface, uint32_t width, uint32_t height) {
   swapchain_.deinit();
   swapchain_.init(
       {physical_device_.graphics_queue(), physical_device_.present_queue()},
       physical_device_.handle(), device_.handle(), surface_, width, height
   );

   for (const VkFramebuffer framebuffer : framebuffers_) {
      vkDestroyFramebuffer(device_.handle(), framebuffer, nullptr);
   }

   create_framebuffers();
}

void Game::begin_preframe() {
   preframe_cmd_buf_ = command_pool_.allocate();

   VkCommandBufferBeginInfo begin_info = {
       .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
       .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
   };

   if (vkBeginCommandBuffer(preframe_cmd_buf_, &begin_info) != VK_SUCCESS) {
      throw std::runtime_error("preframe command buffer couldn't begin recording");
   }
}

void Game::buffer_copy(const StagingBuffer &src, Buffer &dst) {
   VkBufferCopy copy_region = {
       .srcOffset = 0,
       .dstOffset = 0,
       .size = src.size(),
   };
   vkCmdCopyBuffer(preframe_cmd_buf_, src.buffer(), dst.buffer(), 1, &copy_region);
}

void Game::end_preframe() {
   vkEndCommandBuffer(preframe_cmd_buf_);

   VkSubmitInfo submit_info = {
       .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
       .commandBufferCount = 1,
       .pCommandBuffers = &preframe_cmd_buf_,
   };
   vkQueueSubmit(device_.graphics_queue(), 1, &submit_info, VK_NULL_HANDLE);
   vkQueueWaitIdle(device_.graphics_queue());
}

bool Game::poll() {
   Clock::time_point now = Clock::now();
   delta_ = now - last_frame_time_;
   last_frame_time_ = now;

   was_left_clicking_ = window_.left_clicking();
   last_width_ = window_.width();
   last_height_ = window_.height();
   return window_.poll();
}

bool Game::begin_draw(const Pipeline &pipeline) {
   vkWaitForFences(device_.handle(), 1, &draw_cycle_complete, VK_TRUE, UINT64_MAX);

   int width = window_.width();
   int height = window_.height();
   bool window_resized = last_width_ != width || last_height_ != height;
   if (window_resized) {
      handle_resize(surface_, width, height);
      return false;
   }

   VkResult next_image_res = vkAcquireNextImageKHR(
       device_.handle(), swapchain_.handle(), UINT64_MAX, sem_img_avail, VK_NULL_HANDLE,
       &current_framebuffer_
   );

   if (next_image_res == VK_ERROR_OUT_OF_DATE_KHR) {
      handle_resize(surface_, width, height);
      return false;
   } else if (next_image_res != VK_SUCCESS) {
      throw std::runtime_error("failed to acquire next swapchain image");
   }

   vkResetFences(device_.handle(), 1, &draw_cycle_complete);
   vkResetCommandBuffer(command_buffer_, 0);

   VkCommandBufferBeginInfo cmd_begin = {
       .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
   };

   if (vkBeginCommandBuffer(command_buffer_, &cmd_begin) != VK_SUCCESS) {
      throw std::runtime_error("the command buffer could not begin recording");
   }

   VkClearValue clear_color = {.color = {0.0f, 0.0f, 0.0f, 1.0f}};
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
   vkCmdBindPipeline(command_buffer_, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.handle());

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
   return true;
}

void Game::set_uniform(const Pipeline &pipeline, VkDescriptorSet descriptor_set, uint32_t offset) {
   uint32_t offsets[] = {offset};
   vkCmdBindDescriptorSets(
       command_buffer_, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout(), 0, 1, &descriptor_set,
       1, offsets
   );
}

void Game::draw(const VertexIndexBuffer &buffer) {
   VkBuffer buffers[] = {buffer.buffer()};
   VkDeviceSize offsets[] = {0};
   vkCmdBindVertexBuffers(command_buffer_, 0, 1, buffers, offsets);
   vkCmdBindIndexBuffer(
       command_buffer_, buffer.buffer(), buffer.index_offset(), VK_INDEX_TYPE_UINT16
   );

   vkCmdDrawIndexed(command_buffer_, buffer.num_indices(), 1, 0, 0, 0);
}

void Game::end_draw() {
   vkCmdEndRenderPass(command_buffer_);

   if (vkEndCommandBuffer(command_buffer_) != VK_SUCCESS) {
      throw std::runtime_error("command buffer couldn't stop recording");
   }

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

   if (vkQueueSubmit(device_.graphics_queue(), 1, &submit_info, draw_cycle_complete) !=
       VK_SUCCESS) {
      throw std::runtime_error("failed to submit command buffer");
   }

   VkSwapchainKHR swap_chains[] = {swapchain_.handle()};
   VkPresentInfoKHR present_info = {
       .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
       .waitSemaphoreCount = 1,
       .pWaitSemaphores = &sem_render_complete,
       .swapchainCount = VILLA_ARRAY_LEN(swap_chains),
       .pSwapchains = swap_chains,
       .pImageIndices = &current_framebuffer_,
   };

   vkQueuePresentKHR(device_.present_queue(), &present_info);
}

void Game::create_framebuffers() {
   framebuffers_.resize(swapchain_.num_images());
   for (int i = 0; i < swapchain_.num_images(); ++i) {
      VkImageView attachments[] = {swapchain_.image_view(i)};

      VkExtent2D extent = swapchain_.extent();
      VkFramebufferCreateInfo create_info = {
          .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
          .renderPass = render_pass_,
          .attachmentCount = VILLA_ARRAY_LEN(attachments),
          .pAttachments = attachments,
          .width = extent.width,
          .height = extent.height,
          .layers = 1,
      };

      if (vkCreateFramebuffer(device_.handle(), &create_info, nullptr, &framebuffers_[i]) !=
          VK_SUCCESS) {
         throw std::runtime_error(std::format("failed to create framebuffer {}", i));
      }
   }
}
