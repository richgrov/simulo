![vkad logo](.github/logo.svg)

A simple, minimal-dependency CAD program powered by Vulkan

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
