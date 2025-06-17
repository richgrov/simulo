unsafe extern "C" {
    fn simulo_create_object(x: f32, y: f32) -> u32;
    fn simulo_set_object_position(id: u32, x: f32, y: f32);
    fn simulo_set_object_scale(id: u32, x: f32, y: f32);
    fn simulo_delete_object(id: u32);
}

#[unsafe(no_mangle)]
pub extern "C" fn init(root: u32) {
    unsafe {
        let object_id = simulo_create_object(50.0, 50.0);

        simulo_set_object_position(object_id, 500.0, 500.0);

        simulo_set_object_scale(object_id, 250.0, 250.0);

        simulo_delete_object(object_id);
    }
}
