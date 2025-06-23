#pragma once

#include <cstdint>
#include <span>
#include <vector>

#include "render/renderer.h"

namespace simulo {

class Renderer;

template <class Vertex> class Mesh {
public:
   Mesh(std::vector<Vertex> &&vertices, std::vector<Renderer::IndexBufferType> &&indices)
       : vertices_(vertices), indices_(indices) {}

   void add_all(Mesh &other) {
      Renderer::IndexBufferType verts = vertices_.size();
      vertices_.insert(vertices_.end(), other.vertices_.begin(), other.vertices_.end());

      for (auto index : other.indices_) {
         indices_.push_back(verts + index);
      }
   }

   inline std::vector<Vertex> &vertices() {
      return vertices_;
   }

   std::span<uint8_t> vertex_data() {
      return std::span<uint8_t>(
          reinterpret_cast<uint8_t *>(vertices_.data()), vertices_.size() * sizeof(Vertex)
      );
   }

   inline std::vector<Renderer::IndexBufferType> &indices() {
      return indices_;
   }

protected:
   std::vector<Vertex> vertices_;
   std::vector<Renderer::IndexBufferType> indices_;
};

} // namespace simulo
