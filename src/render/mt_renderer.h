#pragma once

#include <span>
#include <utility>
#include <variant>

#include "math/mat4.h"
#include "math/vector.h"

namespace vkad {

enum RenderPipeline : int {};
enum RenderMaterial : int {};
enum RenderMesh : int {};
enum RenderObject : int {};
enum RenderImage : int {};

struct Pipelines {
   RenderPipeline ui;
   RenderPipeline mesh;
};

class MaterialProperties {
public:
   using MaterialPropertyValue = std::variant<Vec3, RenderImage>;

   MaterialProperties(
       const std::initializer_list<std::pair<const std::string, MaterialPropertyValue>> &&kv_pairs
   )
       : properties_(std::move(kv_pairs)) {}

   template <class T> T get(const std::string &key) const {
      if (!properties_.contains(key)) {
         return T();
      }

      const MaterialPropertyValue &value = properties_.at(key);
      if (!std::holds_alternative<T>(value)) {
         return T();
      }

      return std::get<T>(value);
   }

   bool has(const std::string &key) const {
      return properties_.contains(key);
   }

private:
   std::unordered_map<std::string, MaterialPropertyValue> properties_;
};

class Renderer {
public:
   using IndexBufferType = uint32_t;

   template <class Uniform>
   RenderMaterial create_material(RenderPipeline pipeline_id, const MaterialProperties &props) {
      return static_cast<RenderMaterial>(0);
   }

   RenderMesh
   create_mesh(const std::span<uint8_t> vertex_data, const std::span<IndexBufferType> index_data) {
      return static_cast<RenderMesh>(0);
   }

   void delete_mesh(RenderMesh mesh) const {}

   RenderObject add_object(RenderMesh mesh, Mat4 transform, RenderMaterial material) const {
      return static_cast<RenderObject>(0);
   }

   void delete_object(RenderObject object) {}

   RenderImage create_image(std::span<uint8_t> img_data, int width, int height) {
      return static_cast<RenderImage>(0);
   }

   bool render(Mat4 ui_view_projection, Mat4 world_view_projection) {
      return false;
   }

   void recreate_swapchain() const {}

   void wait_idle() {}

   const Pipelines &pipelines() {
      return pipelines_;
   }

private:
   Pipelines pipelines_;
};

} // namespace vkad
