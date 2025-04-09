#include <gdextension_interface.h>
#include <godot_cpp/classes/global_constants.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include "../perception.h"

using namespace godot;

namespace godot {

class Detection : public RefCounted {
   GDCLASS(Detection, RefCounted);

public:
   Detection() {}

   Variant get_keypoint(int keypoint_index) {
      if (keypoint_index < 0 || keypoint_index >= detection_.points.size()) {
         UtilityFunctions::push_error("keypoint index out of range");
         return ERR_INVALID_PARAMETER;
      }

      simulo::Perception::Keypoint kp = detection_.points[keypoint_index];
      return Vector2(kp.x, kp.y);
   }

   simulo::Perception::Detection detection_;

protected:
   static void _bind_methods() {
      ClassDB::bind_method(D_METHOD("get_keypoint", "keypoint_index"), &Detection::get_keypoint);
   }
};

class Perception2d : public Node {
   GDCLASS(Perception2d, Node);

public:
   Perception2d() {
      perception_.set_running(true);
   }

   ~Perception2d() {
      perception_.set_running(false);
   }

   Array detect() {
      std::vector<simulo::Perception::Detection> detections = perception_.latest_detections();

      Array result;
      for (auto &&detection : detections) {
         Ref<Detection> det;
         det.instantiate();
         det->detection_ = std::move(detection);
         result.push_back(det);
      }

      return result;
   }

protected:
   static void _bind_methods() {
      ClassDB::bind_method(D_METHOD("detect"), &Perception2d::detect);
   }

private:
   simulo::Perception perception_;
};

} // namespace godot

void init_perception(ModuleInitializationLevel level) {
   if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
      return;
   }

   GDREGISTER_RUNTIME_CLASS(Detection);
   GDREGISTER_RUNTIME_CLASS(Perception2d);
}

extern "C" {

GDExtensionBool GDE_EXPORT perception_extension_init(
    GDExtensionInterfaceGetProcAddress get_proc_address, const GDExtensionClassLibraryPtr lib,
    GDExtensionInitialization *init
) {
   godot::GDExtensionBinding::InitObject init_object(get_proc_address, lib, init);

   init_object.register_initializer(init_perception);
   init_object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
   return init_object.init();
}
}
