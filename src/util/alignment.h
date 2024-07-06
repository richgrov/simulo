#ifndef VILLA_UTIL_ALIGNMENT_H_
#define VILLA_UTIL_ALIGNMENT_H_

namespace villa {

template <class T> T align_to(T size, T min_alignment) {
   return (size + min_alignment - 1) & ~(min_alignment - 1);
}

} // namespace villa

#endif // !VILLA_UTIL_ALIGNMENT_H_
