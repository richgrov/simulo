#ifndef VKAD_TTF_TTF_H_
#define VKAD_TTF_TTF_H_

#include <cstdint>
#include <span>

namespace vkad {

void read_ttf(const std::span<uint8_t> data);

} // namespace vkad

#endif // !VKAD_TTF_TTF_H_
