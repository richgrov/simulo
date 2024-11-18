![vkad logo](.github/logo.svg)

A simple, minimal-dependency CAD program featuring:

-  Custom Vulkan render backend
-  Windows, X11, and Wayland windowing system from scratch
-  Custom math utilities (Matrix, Vector)

# Setup

Download the [Vulkan SDK](https://vulkan.lunarg.com/)

Compile shaders:

Windows: `./recompile_shaders.ps1`

Build & run:

```
mkdir build
cmake -B build
cmake --build build
./build/example/example(.exe)
```
