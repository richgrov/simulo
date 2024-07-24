#include "model.h"
#include "stl.h"

using namespace vkad;

std::vector<Triangle> Model::to_stl_triangles() const {
   std::vector<Triangle> triangles(indices_.size() / 3);

   for (int i = 0; i < indices_.size(); i += 3) {
      triangles.push_back(Triangle{
          .points =
              {
                  vertices_[indices_[i]].pos,
                  vertices_[indices_[i + 1]].pos,
                  vertices_[indices_[i + 2]].pos,
              },
          .normal = vertices_[indices_[i]].norm,
      });
   }

   return triangles;
}
