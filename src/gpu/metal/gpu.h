#pragma once

namespace vkad {

class Gpu {
public:
   Gpu();
   ~Gpu();

   void *device() const {
      return mt_device_;
   }

private:
   void *mt_device_;
   void *library_;
};

} // namespace vkad
