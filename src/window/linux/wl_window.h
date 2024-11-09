#ifndef VKAD_WINDOW_LINUX_WL_WINDOW_H_
#define VKAD_WINDOW_LINUX_WL_WINDOW_H_

#include "gpu/instance.h"
#include "window/linux/window.h"

struct wl_display;
struct wl_registry;
struct wl_compositor;
struct wl_surface;

namespace vkad {

void handle_global(
    void *user_ptr, wl_registry *registry, uint32_t id, const char *interface, uint32_t version
);

class WaylandWindow : public Window {
public:
   WaylandWindow(const Instance &vk_instance, const char *title);

   ~WaylandWindow();

   virtual bool poll() override;

   virtual void set_capture_mouse(bool capture) override {}

   virtual void request_close() override {}

   virtual inline VkSurfaceKHR surface() const override {
      return nullptr;
   }

   virtual int width() const override {
      return 0;
   }

   virtual int height() const override {
      return 0;
   }

   virtual int mouse_x() const override {
      return 0;
   }

   virtual int mouse_y() const override {
      return 0;
   }

   virtual int delta_mouse_x() const override {
      return 0;
   }

   virtual int delta_mouse_y() const override {
      return 0;
   }

   virtual bool left_clicking() const override {
      return false;
   }

   virtual bool is_key_down(uint8_t key_code) const override {
      return false;
   }

   virtual bool key_just_pressed(uint8_t key_code) const override {
      return false;
   }

   virtual std::string_view typed_chars() const override {
      return "";
   }

private:
   friend void vkad::handle_global(
       void *user_ptr, wl_registry *registry, uint32_t id, const char *interface, uint32_t version
   );

   wl_display *display_;
   wl_compositor *compositor_;
   wl_surface *surface_;
};

} // namespace vkad

#endif // !VKAD_WINDOW_LINUX_WL_WINDOW_H_
