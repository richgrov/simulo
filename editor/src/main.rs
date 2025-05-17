mod simulo_cc;

use std::ffi::CString;

use autocxx::WithinUniquePtr;
use cxx::UniquePtr;

struct Editor {
    gpu: UniquePtr<simulo_cc::Gpu>,
    renderer: UniquePtr<simulo_cc::Renderer>,
    window: UniquePtr<simulo_cc::Window>,
}

impl Editor {
    pub fn new() -> Editor {
        let mut gpu = simulo_cc::Gpu::new().within_unique_ptr();
        let window = unsafe {
            let window_title = CString::new("Simulo Editor").unwrap();
            simulo_cc::Window::new(gpu.as_ref().unwrap(), window_title.as_ptr()).within_unique_ptr()
        };

        let pixel_fmt = window.as_ref().unwrap().layer_pixel_format();
        let metal_layer = window.as_ref().unwrap().metal_layer();
        let renderer = unsafe {
            simulo_cc::Renderer::new(gpu.pin_mut(), pixel_fmt, metal_layer).within_unique_ptr()
        };

        Editor {
            gpu,
            window,
            renderer,
        }
    }

    pub fn run(&mut self) {
        while self.window.as_mut().unwrap().poll() {
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
    }
}

fn main() {
    let mut editor = Editor::new();
    editor.run();
}
