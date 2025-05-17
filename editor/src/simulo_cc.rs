use autocxx::prelude::*;

include_cpp! {
    #include "gpu/gpu.h"
    #include "render/renderer.h"
    #include "util/slab.h"
    #include "window/window.h"
    safety!(unsafe)
    generate!("simulo::Gpu")
    generate!("simulo::Window")
    generate!("simulo::Renderer")
}

pub use ffi::simulo::*;
