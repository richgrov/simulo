#include "simulo__pre.h"

class Particle : public RenderedObject {
public:
   Particle(glm::vec2 position, const Material &material, uint32_t layer) : RenderedObject(material, layer) {
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

   void on_create() {
      Material particle_material(nullptr, 0.0f, 1.0f, 1.0f);
      for (int i = -2; i <= 2; i++) {
         float offset = i * 10.0f;
         float scale_offset = i / 2.0f;
         glm::vec2 position = glm::vec2(simulo_window_width() / 2 + offset, simulo_window_height() / 2 + offset);
         uint32_t layer = static_cast<uint32_t>((i + 2) % 4);
         auto particle = std::make_unique<Particle>(position, particle_material, layer);
         particle->scale += scale_offset;
         add_child(std::unique_ptr<Particle>(std::move(particle)));
      }
   }

   void on_pose(int id, std::optional<Pose> pose) {
      // if (pose) {
      //    add_child(std::make_unique<Particle>(pose->nose(), white_material_));
      // }
   }

private:
   Material white_material_;
};

#include "simulo__post.h"