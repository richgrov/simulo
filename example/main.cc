#include <array>
#include <cstring>
#include <optional>
#include <stdio.h>
#include <cstdint>

#include "glm/ext/matrix_transform.hpp"
#include "glm/ext/vector_float2.hpp"
#include "glm/ext/vector_float3.hpp"
#include "glm/gtc/type_ptr.hpp"

static float simulo__pose_data[17 * 2] = {0};
static float simulo__transform_data[16] = {0};

__attribute__((__import_name__("simulo_set_buffers")))
extern void simulo_set_buffers(float *pose, float *transform);

__attribute__((__import_name__("simulo_set_root")))
extern void simulo_set_root(uint32_t id, void *self);

__attribute__((__import_name__("simulo_create_object")))
extern uint32_t simulo_create_object(uint32_t material);

__attribute__((__import_name__("simulo_set_object_ptrs")))
extern void simulo_set_object_ptrs(uint32_t id, void *self);

__attribute__((__import_name__("simulo_add_object_child")))
extern void simulo_add_object_child(uint32_t parent, uint32_t child);

__attribute__((__import_name__("simulo_get_children")))
extern uint32_t simulo_get_children(uint32_t id, void *children, uint32_t count);

__attribute__((__import_name__("simulo_mark_transform_outdated")))
extern void simulo_mark_transform_outdated(uint32_t id);

__attribute__((__import_name__("simulo_set_object_material")))
extern void simulo_set_object_material(uint32_t id, uint32_t material);

__attribute__((__import_name__("simulo_remove_object_from_parent")))
extern void simulo_remove_object_from_parent(uint32_t id);

__attribute__((__import_name__("simulo_drop_object")))
extern void simulo_drop_object(uint32_t);

__attribute__((__import_name__("simulo_random")))
extern float simulo_random(void);

__attribute__((__import_name__("simulo_window_width")))
extern int32_t simulo_window_width(void);

__attribute__((__import_name__("simulo_window_height")))
extern int32_t simulo_window_height(void);

__attribute__((__import_name__("simulo_create_material")))
extern uint32_t simulo_create_material(uint32_t image, float r, float g, float b);

__attribute__((__import_name__("simulo_delete_material")))
extern void simulo_delete_material(uint32_t id);

extern "C" void simulo__pose(int id, bool alive);

class Pose {
public:
   glm::vec2 nose() const {
      return glm::vec2(data_[0], data_[1]);
   }

   glm::vec2 left_eye() const {
      return glm::vec2(data_[1], data_[2]);
   }

   glm::vec2 right_eye() const {
      return glm::vec2(data_[2], data_[3]);
   }

   glm::vec2 left_ear() const {
      return glm::vec2(data_[3], data_[4]);
   }

   glm::vec2 right_ear() const {
      return glm::vec2(data_[4], data_[5]);
   }

   glm::vec2 left_shoulder() const {
      return glm::vec2(data_[5], data_[6]);
   }

   glm::vec2 right_shoulder() const {
      return glm::vec2(data_[7], data_[8]);
   }

   glm::vec2 left_elbow() const {
      return glm::vec2(data_[8], data_[9]);
   }

   glm::vec2 right_elbow() const {
      return glm::vec2(data_[9], data_[10]);
   }

   glm::vec2 left_wrist() const {
      return glm::vec2(data_[10], data_[11]);
   }

   glm::vec2 right_wrist() const {
      return glm::vec2(data_[11], data_[12]);
   }

   glm::vec2 left_hip() const {
      return glm::vec2(data_[12], data_[13]);
   }

   glm::vec2 right_hip() const {
      return glm::vec2(data_[13], data_[14]);
   }

   glm::vec2 left_knee() const {
      return glm::vec2(data_[14], data_[15]);
   }

   glm::vec2 right_knee() const {
      return glm::vec2(data_[15], data_[16]);
   }

   glm::vec2 left_ankle() const {
      return glm::vec2(data_[16], data_[17]);
   }

   glm::vec2 right_ankle() const {
      return glm::vec2(data_[17], data_[18]);
   }

private:
   friend void ::simulo__pose(int id, bool alive);

   Pose(float *data) {
      std::memcpy(data_.data(), data, sizeof(data_));
   }

   std::array<float, 17 * 2> data_;
};

class Material;
class Object;

class Material {
public:
   Material(uint32_t image, float r, float g, float b) : simulo__id(simulo_create_material(image, r, g, b)) {}

   static Material kWhiteSolid;

private:
   Material() : simulo__id(0) {}

   friend class Object;
   uint32_t simulo__id;
};

Material Material::kWhiteSolid;

extern "C" void simulo__start();

class Object {
public:
   Object(const Material &material) : simulo__id(simulo_create_object(material.simulo__id)) {}

   Object(const Object &) = delete;
   Object &operator=(const Object &) = delete;
   Object(Object &&) = delete;
   Object &operator=(Object &&) = delete;

   virtual ~Object() {
      simulo_drop_object(simulo__id);
   }

   virtual void update(float delta) {}

   virtual glm::mat4 recalculate_transform() {
      return glm::translate(glm::mat4(1.0f), glm::vec3(position, 0.0f)) * glm::rotate(glm::mat4(1.0f), rotation, glm::vec3(0.0f, 0.0f, 1.0f)) * glm::scale(glm::mat4(1.0f), glm::vec3(scale, 1.0f));
   }

   void transform_outdated() {
      simulo_mark_transform_outdated(simulo__id);
   }

   void add_child(Object *object) {
      simulo_set_object_ptrs(object->simulo__id, object);
      simulo_add_object_child(simulo__id, object->simulo__id);
   }

   void delete_from_parent() {
      simulo_remove_object_from_parent(simulo__id);
   }

public:
   glm::vec2 position;
   float rotation;
   glm::vec2 scale;

private:
   friend void ::simulo__start();
   uint32_t simulo__id;
};

class Particle : public Object {
public:
   Particle(glm::vec2 position) : Object(Material::kWhiteSolid) {
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
   Game() : Object(Material::kWhiteSolid) {}

   void on_pose(int id, std::optional<Pose> pose) {
      if (pose) {
         add_child(new Particle(pose->nose()));
      }
   }
};

glm::ivec2 window_size() {
   return glm::ivec2(simulo_window_width(), simulo_window_height());
}

static Game *root_object;

extern "C" {
void simulo__start() {
   Material::kWhiteSolid = Material(std::numeric_limits<uint32_t>::max(), 1.0f, 1.0f, 1.0f);

   Game *object = new Game();
   root_object = object;

   simulo_set_buffers(simulo__pose_data, simulo__transform_data);
   simulo_set_root(object->simulo__id, object);
}

void simulo__update(void* ptr, float delta) {
   Object *object = static_cast<Object *>(ptr);
   object->update(delta);
}

void simulo__recalculate_transform(void* ptr) {
   Object *object = static_cast<Object *>(ptr);
   glm::mat4 transform = object->recalculate_transform();
   std::memcpy(simulo__transform_data, glm::value_ptr(transform), sizeof(simulo__transform_data));
}

void simulo__pose(int id, bool alive) {
   root_object->on_pose(id, alive ? std::optional<Pose>(Pose(simulo__pose_data)) : std::nullopt);
}

void simulo__drop(void* ptr) {
   Object *object = static_cast<Object *>(ptr);
   delete object;
}

}