#ifndef VKAD_UTIL_MEMORY_H_
#define VKAD_UTIL_MEMORY_H_

namespace vkad {

#define VKAD_ARRAY_LEN(x) sizeof(x) / sizeof(0 [x])

template <class T> T align_to(T size, T min_alignment) {
   return (size + min_alignment - 1) & ~(min_alignment - 1);
}

} // namespace vkad

#endif // !VKAD_UTIL_MEMORY_H_
