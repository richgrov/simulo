![simulo logo](.github/simulo-banner.png)

# simulo

Software for creating and managing projection mapping experiences.

## Features

- 🎥 Make interactive experiences through real-time pose detection
- 📡 Automatically calibrate cameras and projectors
- 🎨 Low-overhead rendering directly to HDMI output
- 🤖 [AI-powered editor and simulation engine](https://github.com/richgrov/simulo-editor)
- 🌐 Cloud connectivity for remote control and monitoring
- 🔒 Robust error handling & fully offline capable
- 🕶️ Real-time masking to avoid shining light directly into eyes

## Mission

I hope to make this a tool to create games in the real world through simulation of physics,
robotics, and computer vision. Entertainment is at the core of what motivates young thinkers to do
great things, and there's no reason critical thinking, socialization, and physical activity can't
come with it.

# Prerequisites

**simulo is only supported on the following platforms:**

- macOS: Metal
- Linux: Vulkan & NVIDIA

In order to authenticate with the backend and receive live updates, a keypair and machine ID is
needed. Generate one like so:

```
export SIMULO_MACHINE_ID=0 # any non-negative number
mkdir -p ~/.simulo
openssl genpkey -algorithm ED25519 -outform DER -out ~/.simulo/private.der
openssl pkey -in ~/.simulo/private.der -inform DER -pubout -outform PEM -out ~/.simulo/public.pem
```

**Dependencies:**

- OpenCV
- ONNXRuntime
- WebAssembly Micro Runtime

MacOS:

- Install the dependencies using homebrew
```
brew install zig
brew install opencv wasm-micro-runtime
```

- Locally install the ONNXRuntime by running these commands
```
mkdir -p extern/onnxruntime
curl -L https://github.com/microsoft/onnxruntime/releases/download/v1.22.0/onnxruntime-osx-arm64-1.22.0.tgz -o onnxruntime.tgz
tar -xzf onnxruntime.tgz -C extern/onnxruntime --strip-components=1
```

- Build the project
```
zig build install --search-prefix extern/onnxruntime
```

- Run the tests
```
zig build test
```

Linux:

- [Vulkan SDK](https://vulkan.lunarg.com/)
- `libx11`
- `libxkbcommon`
- Wayland protocols
- TensorRT

**Build**

1. [Build WAMR](https://github.com/bytecodealliance/wasm-micro-runtime/blob/main/product-mini/README.md)
