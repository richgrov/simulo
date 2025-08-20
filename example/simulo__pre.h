#include <array>
#include <cstring>
#include <optional>
#include <stdio.h>
#include <cstdint>
#include <memory>
#include <vector>

#include "glm/ext/matrix_transform.hpp"
#include "glm/ext/vector_float2.hpp"
#include "glm/ext/vector_float3.hpp"
#include "glm/gtc/type_ptr.hpp"

__attribute__((__import_name__("simulo_set_buffers")))
extern void simulo_set_buffers(float *pose, float *transform);

__attribute__((__import_name__("simulo_set_root")))
extern void simulo_set_root(uint32_t id, void *self);

__attribute__((__import_name__("simulo_create_object")))
extern uint32_t simulo_create_object();

__attribute__((__import_name__("simulo_set_object_ptrs")))
extern void simulo_set_object_ptrs(uint32_t id, void *self);

__attribute__((__import_name__("simulo_add_object_child")))
extern void simulo_add_object_child(uint32_t parent, uint32_t child);

__attribute__((__import_name__("simulo_num_children")))
extern uint32_t simulo_num_children(uint32_t id);

__attribute__((__import_name__("simulo_get_children")))
extern void simulo_get_children(uint32_t id, void *children);

__attribute__((__import_name__("simulo_mark_transform_outdated")))
extern void simulo_mark_transform_outdated(uint32_t id);

__attribute__((__import_name__("simulo_remove_object_from_parent")))
extern void simulo_remove_object_from_parent(uint32_t id);

__attribute__((__import_name__("simulo_drop_object")))
extern void simulo_drop_object(uint32_t);

__attribute__((__import_name__("simulo_create_rendered_object")))
extern uint32_t simulo_create_rendered_object(uint32_t material);

__attribute__((__import_name__("simulo_set_rendered_object_material")))
extern void simulo_set_rendered_object_material(uint32_t id, uint32_t material);

__attribute__((__import_name__("simulo_set_rendered_object_transform")))
extern void simulo_set_rendered_object_transform(uint32_t id, const float *transform);

__attribute__((__import_name__("simulo_drop_rendered_object")))
extern void simulo_drop_rendered_object(uint32_t id);

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
      return glm::vec2(data_[2], data_[3]);
   }

   glm::vec2 right_eye() const {
      return glm::vec2(data_[4], data_[5]);
   }

   glm::vec2 left_ear() const {
      return glm::vec2(data_[6], data_[7]);
   }

   glm::vec2 right_ear() const {
      return glm::vec2(data_[8], data_[9]);
   }

   glm::vec2 left_shoulder() const {
      return glm::vec2(data_[10], data_[11]);
   }

   glm::vec2 right_shoulder() const {
      return glm::vec2(data_[12], data_[13]);
   }

   glm::vec2 left_elbow() const {
      return glm::vec2(data_[14], data_[15]);
   }

   glm::vec2 right_elbow() const {
      return glm::vec2(data_[16], data_[17]);
   }

   glm::vec2 left_wrist() const {
      return glm::vec2(data_[18], data_[19]);
   }

   glm::vec2 right_wrist() const {
      return glm::vec2(data_[20], data_[21]);
   }

   glm::vec2 left_hip() const {
      return glm::vec2(data_[22], data_[23]);
   }

   glm::vec2 right_hip() const {
      return glm::vec2(data_[24], data_[25]);
   }

   glm::vec2 left_knee() const {
      return glm::vec2(data_[26], data_[27]);
   }

   glm::vec2 right_knee() const {
      return glm::vec2(data_[28], data_[29]);
   }

   glm::vec2 left_ankle() const {
      return glm::vec2(data_[30], data_[31]);
   }

   glm::vec2 right_ankle() const {
      return glm::vec2(data_[32], data_[33]);
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

private:
   friend class Object;
   friend class RenderedObject;
   uint32_t simulo__id;
};

static uint32_t kSolidTexture;

extern "C" void simulo__start();

class Object {
public:
   Object() : simulo__id(simulo_create_object()) {}

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

   void add_child(std::unique_ptr<Object> object) {
      int id = object->simulo__id;
      simulo_set_object_ptrs(id, object.release());
      simulo_add_object_child(simulo__id, id);
   }

   std::vector<Object *> children() const {
      std::vector<Object *> children(simulo_num_children(simulo__id));
      simulo_get_children(simulo__id, children.data());
      return children;
   }

   void delete_from_parent() {
      simulo_remove_object_from_parent(simulo__id);
   }

   glm::vec2 position;
   float rotation;
   glm::vec2 scale{1.0f, 1.0f};

private:
   friend void ::simulo__start();
   uint32_t simulo__id;
};

class RenderedObject : public Object {
public:
   RenderedObject(const Material &material) : Object(), simulo__render_id(simulo_create_rendered_object(material.simulo__id)) {
      transform_outdated();
   }

   virtual glm::mat4 recalculate_transform() override {
      glm::mat4 transform = Object::recalculate_transform();
      simulo_set_rendered_object_transform(simulo__render_id, glm::value_ptr(transform));
      return transform;
   }

   virtual ~RenderedObject() {
      simulo_drop_rendered_object(simulo__render_id);
   }

private:
   uint32_t simulo__render_id;
};

glm::ivec2 window_size() {
   return glm::ivec2(simulo_window_width(), simulo_window_height());
}

float random_float() {
   return simulo_random();
}
