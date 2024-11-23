#include "scene.h"

#include "geometry/geometry.h"
#include "renderer.h"
#include "res/model.frag.h"
#include "res/model.vert.h"
#include "res/text.frag.h"
#include "res/text.vert.h"
#include "ui/ui.h"

using namespace vkad;

SceneGraph::SceneGraph(Renderer &renderer) : renderer_(renderer) {
   pipelines_.ui = renderer_.create_pipeline<UiVertex>(
       {{std::span(shader_text_vert, shader_text_vert_len), false},
        {std::span(shader_text_frag, shader_text_frag_len), true}},
       {
           DescriptorPool::uniform_buffer_dynamic(0),
           DescriptorPool::combined_image_sampler(1),
       }
   );

   pipelines_.mesh = renderer_.create_pipeline<ModelVertex>(
       {{std::span(shader_model_vert, shader_model_vert_len), false},
        {std::span(shader_model_frag, shader_model_frag_len), true}},
       {DescriptorPool::uniform_buffer_dynamic(0)}
   );
}
