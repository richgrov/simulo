unsafe extern "C" {
    fn simulo_create_object(x: f32, y: f32) -> u32;
}

#[unsafe(no_mangle)]
pub extern "C" fn init(root: u32) {
    unsafe {
        simulo_create_object(0.5, 0.6);
    }
}
