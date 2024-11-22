![vkad logo](.github/logo.svg)

A simple, minimal-dependency CAD program featuring:

-  Custom Vulkan render backend
-  Windows, X11, and Wayland windowing system from scratch
-  Custom math utilities (Matrix, Vector)

I started this project for two reasons:

-  Lack of good CAD software on Linux
-  Learn the ins and outs of graphics development

**TODO / Roadmap:**

-  Custom font renderer implementation
-  Image loading without `stb_image`
-  SIMD Math Acceleration
-  Refactor renderer to be more flexible
-  UI Framework

# Setup

Download `xxd` and the [Vulkan SDK](https://vulkan.lunarg.com/)

Compile shaders:

Windows: `./recompile_shaders.ps1`

Build & run:

```
mkdir build
cmake -B build
cmake --build build
./build/example/example(.exe)
```
