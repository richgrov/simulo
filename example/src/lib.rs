pub struct GameObject(u32);

#[allow(dead_code)]
impl GameObject {
    pub fn new(position: glam::Vec2, material: &Material) -> Self {
        let id = unsafe { simulo_create_object(position.x, position.y, material.0) };
        GameObject(id)
    }

    pub fn position(&self) -> glam::Vec2 {
        unsafe { glam::Vec2::new(simulo_get_object_x(self.0), simulo_get_object_y(self.0)) }
    }

    pub fn set_position(&self, pos: glam::Vec2) {
        unsafe {
            simulo_set_object_position(self.0, pos.x, pos.y);
        }
    }

    pub fn set_scale(&self, scale: glam::Vec2) {
        unsafe {
            simulo_set_object_scale(self.0, scale.x, scale.y);
        }
    }

    pub fn set_material(&self, material: &Material) {
        unsafe {
            simulo_set_object_material(self.0, material.0);
        }
    }

    pub fn delete(&self) {
        unsafe {
            simulo_delete_object(self.0);
        }
    }
}

pub struct Material(u32);

impl Material {
    pub fn new(image_id: u32, r: f32, g: f32, b: f32) -> Self {
        unsafe { Material(simulo_create_material(image_id, r, g, b)) }
    }
}

pub const WHITE_PIXEL_IMAGE: u32 = std::u32::MAX;

pub fn random_float() -> f32 {
    unsafe { simulo_random() }
}

pub fn window_size() -> glam::IVec2 {
    unsafe { glam::IVec2::new(simulo_window_width(), simulo_window_height()) }
}

#[derive(Clone)]
pub struct Pose(pub PoseData);

impl Pose {
    pub fn nose(&self) -> glam::Vec2 {
        self.keypoint(0)
    }

    pub fn left_eye(&self) -> glam::Vec2 {
        self.keypoint(1)
    }

    pub fn right_eye(&self) -> glam::Vec2 {
        self.keypoint(2)
    }

    pub fn left_ear(&self) -> glam::Vec2 {
        self.keypoint(3)
    }

    pub fn right_ear(&self) -> glam::Vec2 {
        self.keypoint(4)
    }

    pub fn left_shoulder(&self) -> glam::Vec2 {
        self.keypoint(5)
    }

    pub fn right_shoulder(&self) -> glam::Vec2 {
        self.keypoint(6)
    }

    pub fn left_elbow(&self) -> glam::Vec2 {
        self.keypoint(7)
    }

    pub fn right_elbow(&self) -> glam::Vec2 {
        self.keypoint(8)
    }

    pub fn left_wrist(&self) -> glam::Vec2 {
        self.keypoint(9)
    }

    pub fn right_wrist(&self) -> glam::Vec2 {
        self.keypoint(10)
    }

    pub fn left_hip(&self) -> glam::Vec2 {
        self.keypoint(11)
    }

    pub fn right_hip(&self) -> glam::Vec2 {
        self.keypoint(12)
    }

    pub fn left_knee(&self) -> glam::Vec2 {
        self.keypoint(13)
    }

    pub fn right_knee(&self) -> glam::Vec2 {
        self.keypoint(14)
    }

    pub fn left_ankle(&self) -> glam::Vec2 {
        self.keypoint(15)
    }

    pub fn right_ankle(&self) -> glam::Vec2 {
        self.keypoint(16)
    }

    fn keypoint(&self, index: usize) -> glam::Vec2 {
        glam::Vec2::new(self.0[index * 2], self.0[index * 2 + 1])
    }
}

static mut GAME: *mut crate::game::Game = std::ptr::null_mut();

type PoseData = [f32; 17 * 2];
static mut POSE_DATA: PoseData = [0.0; 17 * 2];

#[unsafe(no_mangle)]
#[allow(static_mut_refs)]
pub extern "C" fn init(_root: u32) {
    let g = Box::new(crate::game::Game::new());
    unsafe {
        GAME = Box::leak(g);
        simulo_set_pose_buffer(POSE_DATA.as_mut_ptr());
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn update(delta: f32) {
    unsafe {
        (*GAME).update(delta);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn pose(id: u32, alive: bool) {
    unsafe {
        if alive {
            (*GAME).on_pose_update(id, Some(&Pose(POSE_DATA)));
        } else {
            (*GAME).on_pose_update(id, None);
        }
    }
}

unsafe extern "C" {
    fn simulo_set_pose_buffer(data: *mut f32);
    fn simulo_create_object(x: f32, y: f32, material: u32) -> u32;
    fn simulo_set_object_position(id: u32, x: f32, y: f32);
    fn simulo_set_object_scale(id: u32, x: f32, y: f32);
    fn simulo_get_object_x(id: u32) -> f32;
    fn simulo_get_object_y(id: u32) -> f32;
    fn simulo_set_object_material(id: u32, material: u32);
    fn simulo_delete_object(id: u32);
    fn simulo_random() -> f32;
    fn simulo_window_width() -> i32;
    fn simulo_window_height() -> i32;
    fn simulo_create_material(image: u32, r: f32, g: f32, b: f32) -> u32;
}

/////////

mod game {
    use super::*;
    use glam::Vec2;

    pub struct Game {
        obj: GameObject,
    }

    impl Game {
        pub fn new() -> Self {
            let mat = Material::new(0, 1.0, 1.0, 1.0);
            let obj = GameObject::new(Vec2::new(500.0, 500.0), &mat);
            obj.set_scale(Vec2::new(100.0, 100.0));
            Game { obj }
        }

        pub fn update(&mut self, delta: f32) {
            let pos = self.obj.position();
            let dpos = Vec2::new(50.0 * delta, 0.0);
            self.obj.set_position(pos + dpos);
        }

        pub fn on_pose_update(&mut self, id: u32, pose: Option<&Pose>) {
            /*if x == -1.0 && y == -1.0 {
                return;
            }
            self.obj.set_position(x, y);*/
        }
    }
}
