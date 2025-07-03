#[allow(unused)]
unsafe extern "C" {
    fn simulo_create_object(x: f32, y: f32, material: u32) -> u32;
    fn simulo_set_object_position(id: u32, x: f32, y: f32);
    fn simulo_set_object_scale(id: u32, x: f32, y: f32);
    fn simulo_get_object_x(id: u32) -> f32;
    fn simulo_get_object_y(id: u32) -> f32;
    fn simulo_delete_object(id: u32);
    fn simulo_random() -> f32;
    fn simulo_window_width() -> i32;
    fn simulo_window_height() -> i32;
    fn simulo_create_material(r: f32, g: f32, b: f32) -> u32;
}

static mut GAME: *mut Game = std::ptr::null_mut();

#[unsafe(no_mangle)]
pub extern "C" fn init(_root: u32) {
    let g = Box::new(Game::new());
    unsafe {
        GAME = Box::leak(g);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn update(delta: f32) {
    unsafe {
        (*GAME).update(delta);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn pose(id: u32, x: f32, y: f32) {
    unsafe {
        (*GAME).on_pose_update(id, x, y);
    }
}

pub struct GameObject(u32);

#[allow(dead_code)]
impl GameObject {
    pub fn new(x: f32, y: f32, material: u32) -> Self {
        let id = unsafe { simulo_create_object(x, y, material) };
        GameObject(id)
    }

    pub fn set_position(&self, x: f32, y: f32) {
        unsafe {
            simulo_set_object_position(self.0, x, y);
        }
    }

    pub fn x(&self) -> f32 {
        unsafe { simulo_get_object_x(self.0) }
    }

    pub fn y(&self) -> f32 {
        unsafe { simulo_get_object_y(self.0) }
    }

    pub fn set_scale(&self, x: f32, y: f32) {
        unsafe {
            simulo_set_object_scale(self.0, x, y);
        }
    }

    pub fn delete(&self) {
        unsafe {
            simulo_delete_object(self.0);
        }
    }
}

/////////

pub struct Game {
    obj: GameObject,
}

impl Game {
    pub fn new() -> Self {
        let mat = unsafe { simulo_create_material(1.0, 0.5, 0.25) };
        let obj = GameObject::new(500.0, 500.0, mat);
        obj.set_scale(100.0, 100.0);
        Game { obj }
    }

    pub fn update(&mut self, delta: f32) {
        self.obj
            .set_position(self.obj.x() + 50.0 * delta, self.obj.y());
    }

    pub fn on_pose_update(&mut self, id: u32, x: f32, y: f32) {
        /*if x == -1.0 && y == -1.0 {
            return;
        }
        self.obj.set_position(x, y);*/
    }
}
