#include "stl.h"

#include <ios>
#include <ostream>

#include "util/memory.h"

using namespace vkad;

namespace {

void write_traingle(const Triangle &tri, std::ostream &out) {
   out << "facet normal " << tri.normal.x() << " " << tri.normal.y() << " " << tri.normal.z()
       << "\n";

   out << "outer loop\n";
   for (int i = 0; i < VKAD_ARRAY_LEN(tri.points); ++i) {
      Vec3 point = tri.points[i];
      out << "vertex " << point.x() << " " << point.y() << " " << point.z() << "\n";
   }
   out << "endloop\n";

   out << "endfacet\n";
}

} // namespace

void vkad::write_stl(
    const std::string &name, const std::vector<Triangle> triangles, std::ostream &out
) {
   out << "solid " << name << "\n";

   out << std::scientific;
   for (const Triangle &tri : triangles) {
      write_traingle(tri, out);
   }

   out << "endsolid " << name << "\n";
}
