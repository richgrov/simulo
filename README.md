![simulo logo](.github/simulo-banner.png)

# simulo

The game engine of the real world.

Originally called `vkad`, this project began as a CAD program so I could learn about 3D printing
and graphics programming.

I hope to make this a tool to create games in the real world through simulation of physics,
robotics, and computer vision. Entertainment is at the core of what motivates young thinkers to do
great things, and there's no reason critical thinking, socialization, and physical activity can't
come with it.

**Featuring**

- Custom Vulkan and Metal render backend
- Windows, X11, Wayland, and macOS windowing system from scratch
- Custom math utilities (Matrix, Vector)

**TODO / Roadmap:**

- Custom font renderer implementation
- Image loading without `stb_image`
- SIMD Math Acceleration
- Refactor renderer to be more flexible
- UI Framework

# Prerequisites

**simulo is only supported on the following platforms:**

- Windows: Vulkan & NVIDIA
- macOS: Metal
- Linux: Vulkan & NVIDIA

**Dependencies:**

- `xxd`
- OpenCV
- ONNXRuntime

Windows:

- [Vulkan SDK](https://vulkan.lunarg.com/)

Linux:

- [Vulkan SDK](https://vulkan.lunarg.com/)
- `libx11`
- `libxkbcommon`
- Wayland protocols
