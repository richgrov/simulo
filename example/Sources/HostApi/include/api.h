#include <stdint.h>

__attribute__((__import_name__("simulo_set_buffers")))
extern void simulo_set_buffers(float *pose, float *transform);

__attribute__((__import_name__("simulo_set_root")))
extern void simulo_set_root(uint32_t id, void *this);

__attribute__((__import_name__("simulo_create_object")))
extern uint32_t simulo_create_object(uint32_t material);

__attribute__((__import_name__("simulo_set_object_ptrs")))
extern void simulo_set_object_ptrs(uint32_t id, void *this);

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
