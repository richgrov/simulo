#include "pipeline.h"

#include <vulkan/vulkan_core.h>

#include "math/matrix.h"
#include "status.h"
#include "util/memory.h"

using namespace simulo;

Pipeline::Pipeline(
    VkDevice device, VkVertexInputBindingDescription vertex_binding,
    const std::vector<VkVertexInputAttributeDescription> &vertex_attributes,
    const Shader &vertex_shader, const Shader &fragment_shader,
    VkDescriptorSetLayout descriptor_layout, VkRenderPass render_pass
)
    : layout_(VK_NULL_HANDLE), pipeline_(VK_NULL_HANDLE), device_(device) {

   std::array<VkPipelineShaderStageCreateInfo, 2> shader_stages = {
       VkPipelineShaderStageCreateInfo{
           .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
           .stage = VK_SHADER_STAGE_VERTEX_BIT,
           .module = vertex_shader.module(),
           .pName = "main",
       },
       VkPipelineShaderStageCreateInfo{
           .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
           .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
           .module = fragment_shader.module(),
           .pName = "main",
       },
   };

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
       .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,
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
       .dynamicStateCount = VKAD_ARRAY_LEN(dynamic_states),
       .pDynamicStates = dynamic_states,
   };

   VkPushConstantRange push_constants = {
       .stageFlags = VK_SHADER_STAGE_VERTEX_BIT,
       .offset = 0,
       .size = sizeof(Mat4),
   };

   VkPipelineLayoutCreateInfo layout_create = {
       .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
       .setLayoutCount = 1,
       .pSetLayouts = &descriptor_layout,
       .pushConstantRangeCount = 1,
       .pPushConstantRanges = &push_constants,
   };
   VKAD_VK(vkCreatePipelineLayout(device, &layout_create, nullptr, &layout_));

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
       .renderPass = render_pass,
       .subpass = 0,
   };
   VKAD_VK(vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &create_info, nullptr, &pipeline_));
}

Pipeline::~Pipeline() {
   if (pipeline_ != VK_NULL_HANDLE) {
      vkDestroyPipeline(device_, pipeline_, nullptr);
   }

   if (layout_ != VK_NULL_HANDLE) {
      vkDestroyPipelineLayout(device_, layout_, nullptr);
   }
}
