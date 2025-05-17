use autocxx::prelude::*;
use std::ffi::CString;

include_cpp! {
    #include "gpu/gpu.h"
    #include "window/window.h"
    safety!(unsafe)
    generate!("simulo::Gpu")
    generate!("simulo::Window")
}

use ffi::simulo as simulo_cc;

struct Editor {
    gpu: UniquePtr<simulo_cc::Gpu>,
    window: UniquePtr<simulo_cc::Window>,
}

impl Editor {
    pub fn new() -> Editor {
        let gpu = simulo_cc::Gpu::new().within_unique_ptr();
        let window = unsafe {
            let window_title = CString::new("Simulo Editor").unwrap();
            simulo_cc::Window::new(gpu.as_cpp_ref().as_ref(), window_title.as_ptr())
                .within_unique_ptr()
        };

        Editor { gpu, window }
    }
}

fn main() {
    let editor = Editor::new();
    println!("Hello, world!");
    loop {
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
}
