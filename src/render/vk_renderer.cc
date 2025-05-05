#include "vk_renderer.h"

#include <stdexcept>
#include <vector>

#include <vulkan/vulkan_core.h>

#include "gpu/vulkan/buffer.h"
#include "gpu/vulkan/instance.h"
#include "gpu/vulkan/physical_device.h"
#include "gpu/vulkan/pipeline.h"
#include "gpu/vulkan/status.h"
#include "gpu/vulkan/swapchain.h"
#include "math/mat4.h"
#include "mesh.h"
#include "model.h"
#include "res/model.frag.h"
#include "res/model.vert.h"
#include "res/text.frag.h"
#include "res/text.vert.h"
#include "ui.h"
#include "util/memory.h"

using namespace simulo;

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
      materials_(4),
      objects_(16),
      meshes_(16),
      images_(4),
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
       .magFilter = VK_FILTER_LINEAR, // TODO check for support
       .minFilter = VK_FILTER_LINEAR,
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
       sizeof(UiVertex), sizeof(UiUniform),
       {
           VkVertexInputAttributeDescription{
               .location = 0,
               .binding = 0,
               .format = decltype(UiVertex::pos)::format(),
               .offset = offsetof(UiVertex, pos),
           },
           VkVertexInputAttributeDescription{
               .location = 1,
               .binding = 0,
               .format = decltype(UiVertex::tex_coord)::format(),
               .offset = offsetof(UiVertex, tex_coord),
           },
       },
       std::span(shader_text_vert, shader_text_vert_len),
       std::span(shader_text_frag, shader_text_frag_len),
       {
           DescriptorPool::uniform_buffer_dynamic(0),
           DescriptorPool::combined_image_sampler(1),
       }
   );

   pipeline_ids_.mesh = create_pipeline(
       sizeof(ModelVertex), sizeof(ModelUniform),
       {
           VkVertexInputAttributeDescription{
               .location = 0,
               .binding = 0,
               .format = decltype(ModelVertex::pos)::format(),
               .offset = offsetof(ModelVertex, pos),
           },
           VkVertexInputAttributeDescription{
               .location = 1,
               .binding = 0,
               .format = decltype(ModelVertex::norm)::format(),
               .offset = offsetof(ModelVertex, norm),
           },
       },
       std::span(shader_model_vert, shader_model_vert_len),
       std::span(shader_model_frag, shader_model_frag_len),
       {DescriptorPool::uniform_buffer_dynamic(0)}
   );
}

Renderer::~Renderer() {
   device_.wait_idle();

   for (const MaterialPipeline &mat : pipelines_) {
      vkDestroyDescriptorSetLayout(device_.handle(), mat.descriptor_set_layout, nullptr);
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

RenderMesh Renderer::create_mesh(
    std::span<uint8_t> vertex_data, std::span<VertexIndexBuffer::IndexType> index_data
) {
   RenderMesh mesh_id = static_cast<RenderMesh>(meshes_.emplace(Mesh{
       .vertices_indices = VertexIndexBuffer(
           vertex_data.size_bytes(), index_data.size_bytes(), device_.handle(), physical_device_
       ),
   }));
   update_mesh(mesh_id, vertex_data, index_data);
   return mesh_id;
}

RenderObject Renderer::add_object(RenderMesh mesh, Mat4 transform, RenderMaterial material) {
   RenderObject object_id = static_cast<RenderObject>(objects_.emplace(MeshInstance{
       .transform = transform,
       .mesh_id = mesh,
       .material_id = material,
   }));

   Material &mat = materials_.get(material);
   if (mat.instances.contains(mesh)) {
      mat.instances.at(mesh).insert(object_id);
   } else {
      std::unordered_set<RenderObject> instances = {object_id};
      mat.instances.emplace(mesh, std::move(instances));
   }

   return static_cast<RenderObject>(object_id);
}

void Renderer::delete_object(RenderObject object) {
   MeshInstance &instance = objects_.get(object);
   materials_.get(instance.material_id).instances.at(instance.mesh_id).erase(object);
   objects_.release(object);
}

RenderImage Renderer::create_image(std::span<uint8_t> img_data, int width, int height) {
   int image_id = images_.emplace(
       physical_device_, device_.handle(),
       VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT, VK_FORMAT_R8_UNORM, width,
       height
   );
   Image &image = images_.get(image_id);

   staging_buffer_.upload_raw(img_data.data(), img_data.size());
   begin_preframe();
   transfer_image_layout(image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
   upload_texture(staging_buffer_, image);
   transfer_image_layout(image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
   end_preframe();

   image.init_view();
   return static_cast<RenderImage>(image_id);
}

RenderPipeline Renderer::create_pipeline(
    uint32_t vertex_size, VkDeviceSize uniform_size,
    const std::vector<VkVertexInputAttributeDescription> &attrs, std::span<uint8_t> vertex_shader,
    std::span<uint8_t> fragment_shader, const std::vector<VkDescriptorSetLayoutBinding> &bindings
) {
   VkVertexInputBindingDescription binding = {
       .binding = 0,
       .stride = vertex_size,
       .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
   };

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

   Shader vertex(device_, vertex_shader);
   Shader fragment(device_, fragment_shader);

   pipelines_.emplace_back(MaterialPipeline{
       .descriptor_set_layout = layout,
       .pipeline =
           Pipeline(device_.handle(), binding, attrs, vertex, fragment, layout, render_pass_),
       .descriptor_pool = DescriptorPool(device_.handle(), layout, sizes, 1),
       .uniforms = UniformBuffer(uniform_size, 4, device_.handle(), physical_device_),
       .vertex_shader = std::move(vertex),
       .fragment_shader = std::move(fragment),
   });
   return static_cast<RenderPipeline>(pipelines_.size() - 1);
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

bool Renderer::render(Mat4 ui_view_projection, Mat4 world_view_projection) {
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

   draw_pipeline(pipeline_ids_.mesh, world_view_projection);
   draw_pipeline(pipeline_ids_.ui, ui_view_projection);

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
   return true;
}

void Renderer::draw_pipeline(RenderPipeline pipeline_id, Mat4 view_projection) {
   MaterialPipeline &pipe = pipelines_[pipeline_id];
   vkCmdBindPipeline(command_buffer_, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe.pipeline.handle());

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

   for (const int material_id : pipe.materials) {
      Material &mat = materials_.get(material_id);

      uint32_t offsets[] = {0};
      vkCmdBindDescriptorSets(
          command_buffer_, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe.pipeline.layout(), 0, 1,
          &mat.descriptor_set, 1, offsets
      );

      for (const auto &[mesh_id, instances] : mat.instances) {
         // When a mesh is deleted, it's list of instances will be cleared, but not deleted with it.
         // It's important to check this here to prevent out of bounds access and save performance
         if (instances.empty()) {
            continue;
         }

         Mesh &mesh = meshes_.get(mesh_id);

         VkBuffer buffers[] = {mesh.vertices_indices.buffer()};
         VkDeviceSize offsets[] = {0};
         vkCmdBindVertexBuffers(command_buffer_, 0, 1, buffers, offsets);
         vkCmdBindIndexBuffer(
             command_buffer_, mesh.vertices_indices.buffer(), mesh.vertices_indices.index_offset(),
             VK_INDEX_TYPE_UINT16
         );

         for (const int instance_id : instances) {
            MeshInstance &obj = objects_.get(instance_id);
            Mat4 mvp = view_projection * obj.transform;

            vkCmdPushConstants(
                command_buffer_, pipe.pipeline.layout(), VK_SHADER_STAGE_VERTEX_BIT, 0,
                sizeof(Mat4), &mvp
            );

            vkCmdDrawIndexed(command_buffer_, mesh.vertices_indices.num_indices(), 1, 0, 0, 0);
         }
      }
   }
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
