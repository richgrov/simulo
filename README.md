![simulo logo](.github/simulo-banner.png)

# simulo

Software for creating and managing projection mapping experiences.

## Features

- 🎥 Make interactive experiences through real-time pose detection
- 📡 Automatically calibrate cameras and projectors
- 🎨 Low-overhead rendering directly to HDMI output
- 🤖 AI-powered editor and simulation engine
- 🌐 Cloud connectivity for remote control and monitoring
- 🔒 Robust error handling & fully offline capable

## Mission

I hope to make this a tool to create games in the real world through simulation of physics,
robotics, and computer vision. Entertainment is at the core of what motivates young thinkers to do
great things, and there's no reason critical thinking, socialization, and physical activity can't
come with it.

# Prerequisites

**simulo is only supported on the following platforms:**

- macOS: Metal
- Linux: Vulkan & NVIDIA

**Dependencies:**

- OpenCV
- ONNXRuntime
- WebAssembly Micro Runtime

Linux:

- [Vulkan SDK](https://vulkan.lunarg.com/)
- `libx11`
- `libxkbcommon`
- Wayland protocols

**Build**

1. [Build WAMR](https://github.com/bytecodealliance/wasm-micro-runtime/blob/main/product-mini/README.md)
