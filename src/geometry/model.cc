#include "model.h"
#include "stl.h"

using namespace simulo;

static Vec3 swap_yz(Vec3 v) {
   return {v.x(), v.z(), v.y()};
}

std::vector<Triangle> Model::to_stl_triangles() const {
   std::vector<Triangle> triangles(indices_.size() / 3);

   for (int i = 0; i < indices_.size(); i += 3) {
      triangles.push_back(Triangle{
          .points =
              {
                  swap_yz(vertices_[indices_[i]].pos),
                  swap_yz(vertices_[indices_[i + 1]].pos),
                  swap_yz(vertices_[indices_[i + 2]].pos),
              },
          .normal = vertices_[indices_[i]].norm,
      });
   }

   return triangles;
}
