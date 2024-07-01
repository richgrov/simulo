#include "pipeline.h"

#include <functional>
#include <stdexcept>

#include "vulkan/vulkan_core.h"

#include "swapchain.h"
#include "util/array.h"

using namespace villa;

void Pipeline::init(
    VkDevice device, VkVertexInputBindingDescription vertex_binding,
    const std::vector<VkVertexInputAttributeDescription> &vertex_attributes,
    const std::vector<std::reference_wrapper<Shader>> &shaders, const Swapchain &swapchain
) {
   device_ = device;

   std::vector<VkPipelineShaderStageCreateInfo> shader_stages(shaders.size());
   for (int i = 0; i < shader_stages.size(); ++i) {
      shader_stages[i] = shaders[i].get().pipeline_stage();
   }

   VkPipelineVertexInputStateCreateInfo vertex_input_create = {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
       .vertexBindingDescriptionCount = 1,
       .pVertexBindingDescriptions = &vertex_binding,
       .vertexAttributeDescriptionCount = static_cast<uint32_t>(vertex_attributes.size()),
       .pVertexAttributeDescriptions = vertex_attributes.data(),
   };

   VkPipelineInputAssemblyStateCreateInfo assembly_create = {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
       .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
   };

   VkPipelineViewportStateCreateInfo viewport_create = {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
       .viewportCount = 1,
       .scissorCount = 1,
   };

   VkPipelineRasterizationStateCreateInfo rasterizer_create = {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
       .polygonMode = VK_POLYGON_MODE_FILL,
       .cullMode = VK_CULL_MODE_BACK_BIT,
       .frontFace = VK_FRONT_FACE_CLOCKWISE,
       .lineWidth = 1.0f,
   };

   VkPipelineMultisampleStateCreateInfo multisample_create = {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
       .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
   };

   VkPipelineColorBlendAttachmentState color_blend_attachment = {
       .blendEnable = VK_TRUE,
       .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
       .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
       .colorBlendOp = VK_BLEND_OP_ADD,
       .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
       .dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO,
       .alphaBlendOp = VK_BLEND_OP_ADD,
       .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                         VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
   };

   VkPipelineColorBlendStateCreateInfo color_blend_create = {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
       .attachmentCount = 1,
       .pAttachments = &color_blend_attachment,
   };

   VkDynamicState dynamic_states[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
   VkPipelineDynamicStateCreateInfo dynamic_create = {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
       .dynamicStateCount = VILLA_ARRAY_LEN(dynamic_states),
       .pDynamicStates = dynamic_states,
   };

   VkPipelineLayoutCreateInfo layout_create = {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
   };

   if (vkCreatePipelineLayout(device, &layout_create, nullptr, &layout_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create pipeline layout");
   }

   VkAttachmentDescription color_attachment = {
       .format = swapchain.img_format(),
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

   if (vkCreateRenderPass(device, &render_create, nullptr, &render_pass_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create render pass");
   }

   VkGraphicsPipelineCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
       .stageCount = static_cast<uint32_t>(shader_stages.size()),
       .pStages = shader_stages.data(),
       .pVertexInputState = &vertex_input_create,
       .pInputAssemblyState = &assembly_create,
       .pViewportState = &viewport_create,
       .pRasterizationState = &rasterizer_create,
       .pMultisampleState = &multisample_create,
       .pDepthStencilState = nullptr,
       .pColorBlendState = &color_blend_create,
       .pDynamicState = &dynamic_create,
       .layout = layout_,
       .renderPass = render_pass_,
       .subpass = 0,
   };

   if (vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &create_info, nullptr, &pipeline_) !=
       VK_SUCCESS) {
      throw std::runtime_error("failed to create pipeline");
   }
}

void Pipeline::deinit() {
   if (render_pass_ != VK_NULL_HANDLE) {
      vkDestroyRenderPass(device_, render_pass_, nullptr);
   }

   if (pipeline_ != VK_NULL_HANDLE) {
      vkDestroyPipeline(device_, pipeline_, nullptr);
   }

   if (layout_ != VK_NULL_HANDLE) {
      vkDestroyPipelineLayout(device_, layout_, nullptr);
   }
}
