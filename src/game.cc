#include "game.h"

#include <stdexcept>
#include <vector>

#include <fmod.h>
#include <vulkan/vulkan_core.h>

#include "entity/player.h"
#include "gpu/buffer.h"
#include "gpu/instance.h"
#include "gpu/physical_device.h"
#include "gpu/pipeline.h"
#include "gpu/shader.h"
#include "gpu/status.h"
#include "gpu/swapchain.h"
#include "util/memory.h"
#include "window/win32/keys.h"

using namespace vkad;

Game::Game(const char *title)
    : vk_instance_(Window::vulkan_extensions()),
      window_(vk_instance_, title),
      physical_device_(vk_instance_, window_.surface()),
      device_(physical_device_),
      swapchain_(
          {physical_device_.graphics_queue(), physical_device_.present_queue()},
          physical_device_.handle(), device_.handle(), window_.surface(), window_.width(),
          window_.height()
      ),
      render_pass_(VK_NULL_HANDLE),
      was_left_clicking_(false),
      font_("res/arial.ttf", physical_device_, device_.handle()),
      last_frame_time_(Clock::now()),
      delta_(0),
      last_width_(window_.width()),
      last_height_(window_.height()),
      player_(*this) {

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

   vertex_shader_.init(device_.handle(), "shader-vert.spv", ShaderType::kVertex);
   fragment_shader_.init(device_.handle(), "shader-frag.spv", ShaderType::kFragment);

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

   if (FMOD_System_Create(&sound_system_, FMOD_VERSION) != FMOD_OK) {
      throw std::runtime_error("failed to create sound system");
   }

   if (FMOD_System_Init(sound_system_, 32, FMOD_INIT_NORMAL, nullptr) != FMOD_OK) {
      throw std::runtime_error("failed to initialize sound system");
   }

   window_.set_capture_mouse(true);
}

Game::~Game() {
   device_.wait_idle();

   FMOD_System_Release(sound_system_);

   vkDestroySemaphore(device_.handle(), sem_img_avail, nullptr);
   vkDestroySemaphore(device_.handle(), sem_render_complete, nullptr);
   vkDestroyFence(device_.handle(), draw_cycle_complete, nullptr);

   vkDestroySampler(device_.handle(), sampler_, nullptr);

   for (const VkFramebuffer framebuffer : framebuffers_) {
      vkDestroyFramebuffer(device_.handle(), framebuffer, nullptr);
   }

   command_pool_.deinit();

   vertex_shader_.deinit();
   fragment_shader_.deinit();

   if (render_pass_ != VK_NULL_HANDLE) {
      vkDestroyRenderPass(device_.handle(), render_pass_, nullptr);
   }
}

void Game::handle_resize(uint32_t width, uint32_t height) {
   swapchain_ = std::move(Swapchain(
       {physical_device_.graphics_queue(), physical_device_.present_queue()},
       physical_device_.handle(), device_.handle(), window_.surface(), width, height
   ));

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
   VKAD_VK(vkBeginCommandBuffer(preframe_cmd_buf_, &begin_info));
}

void Game::buffer_copy(const StagingBuffer &src, Buffer &dst) {
   VkBufferCopy copy_region = {
       .srcOffset = 0,
       .dstOffset = 0,
       .size = src.size(),
   };
   vkCmdCopyBuffer(preframe_cmd_buf_, src.buffer(), dst.buffer(), 1, &copy_region);
}

void Game::upload_texture(const StagingBuffer &src, Image &image) {
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
   if (window_.is_key_down(VKAD_KEY_ESC)) {
      window_.request_close();
   }

   Clock::time_point now = Clock::now();
   delta_ = now - last_frame_time_;
   last_frame_time_ = now;

   was_left_clicking_ = window_.left_clicking();
   last_width_ = window_.width();
   last_height_ = window_.height();

   if (FMOD_System_Update(sound_system_) != FMOD_OK) {
      throw std::runtime_error("failed to poll fmod system");
   }

   player_.update(delta_.count());

   return window_.poll();
}

bool Game::begin_draw(const Pipeline &pipeline) {
   vkWaitForFences(device_.handle(), 1, &draw_cycle_complete, VK_TRUE, UINT64_MAX);

   int width = window_.width();
   int height = window_.height();
   bool window_resized = last_width_ != width || last_height_ != height;
   if (window_resized) {
      handle_resize(width, height);
      return false;
   }

   VkResult next_image_res = vkAcquireNextImageKHR(
       device_.handle(), swapchain_.handle(), UINT64_MAX, sem_img_avail, VK_NULL_HANDLE,
       &current_framebuffer_
   );

   if (next_image_res == VK_ERROR_OUT_OF_DATE_KHR) {
      handle_resize(width, height);
      return false;
   }

   VKAD_VK(next_image_res);

   vkResetFences(device_.handle(), 1, &draw_cycle_complete);
   vkResetCommandBuffer(command_buffer_, 0);

   VkCommandBufferBeginInfo cmd_begin = {
       .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
   };
   VKAD_VK(vkBeginCommandBuffer(command_buffer_, &cmd_begin));

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

void Game::create_framebuffers() {
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
