#include "simulo__pre.h"

class Particle : public RenderedObject {
public:
   Particle(glm::vec2 position, const Material &material) : RenderedObject(material) {
      this->position = position;
      scale = glm::vec2(10.0f, 10.0f);
      transform_outdated();
   }

   void update(float delta) override {
      position += glm::vec2(0.0f, 20.0f) * delta;
      scale -= glm::vec2(2.0f, 2.0f) * delta;
      transform_outdated();
      if (scale.x <= 0.0f || scale.y <= 0.0f) {
         delete_from_parent();
      }
   }
};

class Game : public Object {
public:
   Game(const Material &material) : white_material_(material) {}

   static std::unique_ptr<Game> create() {
      Material material(nullptr, 1.0f, 1.0f, 1.0f);
      return std::make_unique<Game>(material);
   }

   void on_pose(int id, std::optional<Pose> pose) {
      if (pose) {
         add_child(std::make_unique<Particle>(pose->nose(), white_material_));
      }
   }

private:
   Material white_material_;
};

#include "simulo__post.h"