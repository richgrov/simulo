#pragma once

#ifdef __APPLE__
#include "mt_renderer.h" // IWYU pragma: export
#else
#include "vk_renderer.h" // IWYU pragma: export
#endif
