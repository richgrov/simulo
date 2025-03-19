#pragma once

#include "util/assert.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <utility>
#include <vector>

namespace vkad {

static constexpr int kInvalidSlabKey = -1;

template <class T> class Slab {
public:
   explicit Slab(size_t initial_capacity) : next_available_(kInvalidSlabKey) {
      objects_.reserve(initial_capacity);
      in_use_.reserve(initial_capacity);
   }

   ~Slab() {
      for (int i = 0; i < objects_.size(); ++i) {
         if (in_use_[i]) {
            release(i);
         }
      }
   }

   [[nodiscard]] T &get(const int index) {
      VKAD_DEBUG_ASSERT(
          index >= 0 && index < in_use_.size() && in_use_[index], "index = {}", index
      );
      return get_storage(index).value();
   }

   template <class... Args> int emplace(Args &&...args) {
      if (next_available_ == kInvalidSlabKey) {
         int key = objects_.size();
         objects_.emplace_back();
         get_storage(key).store_value(std::forward<Args>(args)...);
         in_use_.push_back(true);
         return key;
      }

      int key = next_available_;
      auto &storage = get_storage(key);
      next_available_ = storage.next();
      storage.store_value(std::forward<Args>(args)...);
      in_use_[key] = true;
      return key;
   }

   void release(const int key) {
      VKAD_DEBUG_ASSERT(key >= 0 && key < in_use_.size() && in_use_[key], "key = {}", key);

      auto &storage = get_storage(key);
      storage.call_value_destructor();
      storage.store_next(next_available_);
      next_available_ = key;
      in_use_[key] = false;
   }

   bool contains(const int key) {
      return in_use_[key];
   }

private:
   struct Storage {
      static constexpr std::size_t kSize = std::max<std::size_t>({sizeof(int), sizeof(T)});
      static constexpr std::size_t kAlign = std::max<std::size_t>({alignof(int), alignof(T)});
      alignas(kAlign) std::array<uint8_t, kSize> storage;

      int next() {
         auto ptr = reinterpret_cast<int *>(storage.data());
         return *ptr;
      }

      void store_next(const int next) {
         auto ptr = reinterpret_cast<int *>(storage.data());
         *ptr = next;
      }

      template <class... Args> void store_value(Args &&...args) {
         new (storage.data()) T(std::forward<Args>(args)...);
      }

      T &value() {
         auto ptr = reinterpret_cast<T *>(storage.data());
         return *ptr;
      }

      void call_value_destructor() {
         auto ptr = reinterpret_cast<T *>(storage.data());
         ptr->T::~T();
      }
   };

   Storage &get_storage(const int index) {
      return objects_[index];
   }

   std::vector<Storage> objects_;
   std::vector<bool> in_use_;
   int next_available_;
};

} // namespace vkad
