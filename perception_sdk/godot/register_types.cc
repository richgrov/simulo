#include <gdextension_interface.h>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

namespace godot {

class Perception2d : public RefCounted {
   GDCLASS(Perception2d, RefCounted);

public:
   Perception2d() {}
   ~Perception2d() {}

protected:
   static void _bind_methods() {}
};

} // namespace godot

void init_perception(ModuleInitializationLevel level) {
   if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
      return;
   }

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
