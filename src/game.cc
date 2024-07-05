#include "game.h"

#include <format>
#include <optional>
#include <set>
#include <stdexcept>
#include <vector>

#include <vulkan/vulkan_core.h>

#include "gpu/buffer.h"
#include "gpu/instance.h"
#include "gpu/pipeline.h"
#include "gpu/shader.h"
#include "gpu/swapchain.h"
#include "util/array.h"

using namespace villa;

struct villa::QueueFamilies {
   uint32_t graphics;
   uint32_t presentation;
};

namespace {

std::optional<QueueFamilies> get_queue_families(VkPhysicalDevice device, VkSurfaceKHR surface) {
   uint32_t num_queue_families;
   vkGetPhysicalDeviceQueueFamilyProperties(device, &num_queue_families, nullptr);

   std::vector<VkQueueFamilyProperties> queue_families(num_queue_families);
   vkGetPhysicalDeviceQueueFamilyProperties(device, &num_queue_families, queue_families.data());

   QueueFamilies result;
   bool graphics_found = false;
   bool presentation_found = false;

   for (int i = 0; i < queue_families.size(); ++i) {
      if (!graphics_found && (queue_families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) == 1) {
         result.graphics = i;
         graphics_found = true;
      }

      if (!presentation_found) {
         VkBool32 supported = false;
         vkGetPhysicalDeviceSurfaceSupportKHR(device, i, surface, &supported);
         if (supported) {
            result.presentation = i;
            presentation_found = true;
         }
      }
   }

   if (!graphics_found || !presentation_found) {
      return std::nullopt;
   }

   return std::make_optional(result);
}

VkDevice create_logical_device(VkPhysicalDevice phys_device, const QueueFamilies &queue_families) {
   std::set<uint32_t> unique_queue_families = {
       queue_families.graphics, queue_families.presentation
   };

   std::vector<VkDeviceQueueCreateInfo> create_queues;
   create_queues.reserve(2);

   const float queue_priority = 1.0f;
   for (const uint32_t queue_family : unique_queue_families) {
      create_queues.push_back({
          .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
          .queueFamilyIndex = queue_family,
          .queueCount = 1,
          .pQueuePriorities = &queue_priority,
      });
   }

   VkPhysicalDeviceFeatures physical_device_features = {};

   static const char *swapchain_extension = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
   VkDeviceCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
       .queueCreateInfoCount = static_cast<uint32_t>(create_queues.size()),
       .pQueueCreateInfos = create_queues.data(),
#ifdef VILLA_DEBUG
       .enabledLayerCount = VILLA_ARRAY_LEN(validation_layers),
       .ppEnabledLayerNames = validation_layers,
#endif
       .enabledExtensionCount = 1,
       .ppEnabledExtensionNames = &swapchain_extension,
       .pEnabledFeatures = &physical_device_features,
   };

   VkDevice device;
   if (vkCreateDevice(phys_device, &create_info, nullptr, &device) != VK_SUCCESS) {
      throw std::runtime_error("failed to create logical device");
   }

   return device;
}

} // namespace

Game::Game(const char *title)
    : window_(title), vk_instance_(window_.vulkan_extensions()), physical_device_(VK_NULL_HANDLE),
      device_(VK_NULL_HANDLE), surface_(VK_NULL_HANDLE), render_pass_(VK_NULL_HANDLE) {

   auto surface = window_.create_surface(vk_instance_.handle());
   int width = window_.width();
   int height = window_.height();

   surface_ = surface;

   QueueFamilies queue_familes;
   if (!init_physical_device(&queue_familes)) {
      throw std::runtime_error("no suitable physical device");
   }

   device_ = create_logical_device(physical_device_, queue_familes);

   graphics_queue_index_ = queue_familes.graphics;
   present_queue_index_ = queue_familes.presentation;
   vkGetDeviceQueue(device_, graphics_queue_index_, 0, &graphics_queue_);
   vkGetDeviceQueue(device_, present_queue_index_, 0, &present_queue_);

   swapchain_.init(
       {graphics_queue_index_, present_queue_index_}, physical_device_, device_, surface_, width,
       height
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

   if (vkCreateRenderPass(device_, &render_create, nullptr, &render_pass_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create render pass");
   }

   vertex_shader_.init(device_, "shader-vert.spv", ShaderType::kVertex);
   fragment_shader_.init(device_, "shader-frag.spv", ShaderType::kFragment);

   create_framebuffers();

   command_pool_.init(device_, queue_familes.graphics);
   command_buffer_ = command_pool_.allocate();

   VkSemaphoreCreateInfo semaphore_create = {.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
   VkFenceCreateInfo fence_create = {
       .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT
   };

   if (vkCreateSemaphore(device_, &semaphore_create, nullptr, &sem_img_avail) != VK_SUCCESS ||
       vkCreateSemaphore(device_, &semaphore_create, nullptr, &sem_render_complete) != VK_SUCCESS ||
       vkCreateFence(device_, &fence_create, nullptr, &draw_cycle_complete) != VK_SUCCESS) {
      throw std::runtime_error("failed to create semaphore(s)");
   }
}

Game::~Game() {
   vkDeviceWaitIdle(device_);

   vkDestroySemaphore(device_, sem_img_avail, nullptr);
   vkDestroySemaphore(device_, sem_render_complete, nullptr);
   vkDestroyFence(device_, draw_cycle_complete, nullptr);

   for (const VkFramebuffer framebuffer : framebuffers_) {
      vkDestroyFramebuffer(device_, framebuffer, nullptr);
   }

   command_pool_.deinit();

   vertex_shader_.deinit();
   fragment_shader_.deinit();

   if (render_pass_ != VK_NULL_HANDLE) {
      vkDestroyRenderPass(device_, render_pass_, nullptr);
   }

   swapchain_.deinit();

   if (device_ != VK_NULL_HANDLE) {
      vkDestroyDevice(device_, nullptr);
   }

   if (surface_ != VK_NULL_HANDLE) {
      vkDestroySurfaceKHR(vk_instance_.handle(), surface_, nullptr);
   }
}

void Game::handle_resize(VkSurfaceKHR surface, uint32_t width, uint32_t height) {
   swapchain_.deinit();
   swapchain_.init(
       {graphics_queue_index_, present_queue_index_}, physical_device_, device_, surface_, width,
       height
   );

   for (const VkFramebuffer framebuffer : framebuffers_) {
      vkDestroyFramebuffer(device_, framebuffer, nullptr);
   }

   create_framebuffers();
}

void Game::buffer_copy(const StagingBuffer &src, Buffer &dst) {
   VkCommandBuffer cmd_buf = command_pool_.allocate();

   VkCommandBufferBeginInfo begin_info = {
       .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
       .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
   };

   if (vkBeginCommandBuffer(cmd_buf, &begin_info) != VK_SUCCESS) {
      throw std::runtime_error("command buffer for buffer copy couldn't begin recording");
   }

   VkBufferCopy copy_region = {
       .srcOffset = 0,
       .dstOffset = 0,
       .size = src.size(),
   };
   vkCmdCopyBuffer(cmd_buf, src.buffer(), dst.buffer(), 1, &copy_region);
   vkEndCommandBuffer(cmd_buf);

   VkSubmitInfo submit_info = {
       .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
       .commandBufferCount = 1,
       .pCommandBuffers = &cmd_buf,
   };
   vkQueueSubmit(graphics_queue_, 1, &submit_info, VK_NULL_HANDLE);
   vkQueueWaitIdle(graphics_queue_);
}

bool Game::begin_draw(const Pipeline &pipeline, VkDescriptorSet descriptor_set) {
   vkWaitForFences(device_, 1, &draw_cycle_complete, VK_TRUE, UINT64_MAX);

   VkResult next_image_res = vkAcquireNextImageKHR(
       device_, swapchain_.handle(), UINT64_MAX, sem_img_avail, VK_NULL_HANDLE,
       &current_framebuffer_
   );
   if (next_image_res == VK_ERROR_OUT_OF_DATE_KHR) {
      // TODO: Detect with window size change as well
      handle_resize(surface_, width(), height());
      return false;
   } else if (next_image_res != VK_SUCCESS) {
      throw std::runtime_error("failed to acquire next swapchain image");
   }

   vkResetFences(device_, 1, &draw_cycle_complete);
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

   vkCmdBindDescriptorSets(
       command_buffer_, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout(), 0, 1, &descriptor_set,
       0, nullptr
   );
   return true;
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

   if (vkQueueSubmit(graphics_queue_, 1, &submit_info, draw_cycle_complete) != VK_SUCCESS) {
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

   vkQueuePresentKHR(present_queue_, &present_info);
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

      if (vkCreateFramebuffer(device_, &create_info, nullptr, &framebuffers_[i]) != VK_SUCCESS) {
         throw std::runtime_error(std::format("failed to create framebuffer {}", i));
      }
   }
}

bool Game::init_physical_device(QueueFamilies *out_families) {
   uint32_t num_devices;
   vkEnumeratePhysicalDevices(vk_instance_.handle(), &num_devices, nullptr);
   if (num_devices == 0) {
      throw std::runtime_error("no physical devices");
   }

   std::vector<VkPhysicalDevice> devices(num_devices);
   vkEnumeratePhysicalDevices(vk_instance_.handle(), &num_devices, devices.data());

   for (const auto &device : devices) {
      if (!Swapchain::is_supported_on(device, surface_)) {
         continue;
      }

      std::optional<QueueFamilies> queue_familes = get_queue_families(device, surface_);
      if (!queue_familes.has_value()) {
         continue;
      }

      physical_device_ = device;
      *out_families = queue_familes.value();
      return true;
   }

   return false;
}
