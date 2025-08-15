use std::ffi::c_void;
use simulo_declare_type::ObjectClass;

pub trait TypeIdentifiable {
    const TYPE_ID: u32;
}

pub struct BaseObject(u32);

pub trait Object {
    fn base(&self) -> &BaseObject;
    fn update(&mut self, _delta: f32) {}
    fn delete(&mut self) {}

    fn new<T: Object + TypeIdentifiable + 'static>(position: glam::Vec2, material: &Material, f: impl FnOnce(BaseObject) -> T) -> Box<T> {
        let id = unsafe { simulo_create_object(position.x, position.y, material.0) };
        let obj = BaseObject(id);
        let node = f(obj);
        let b = Box::new(node);
        let ptr: *const T = &*b;

        let type_id = T::TYPE_ID;
        unsafe { simulo_set_object_ptr(id, type_id, ptr as *mut T as *mut c_void); }
        b
    }
}

#[allow(dead_code)]
impl BaseObject {
    pub fn new<T: Object + TypeIdentifiable + 'static>(position: glam::Vec2, material: &Material, f: impl FnOnce(BaseObject) -> T) -> Box<T> {
        let id = unsafe { simulo_create_object(position.x, position.y, material.0) };
        let obj = BaseObject(id);
        let node = f(obj);
        let b = Box::new(node);
        let ptr: *const T = &*b;

        let type_id = T::TYPE_ID;
        unsafe { simulo_set_object_ptr(id, type_id, ptr as *mut T as *mut c_void); }
        b
    }

    pub fn add_child(&self, child: Box<impl Object>) {
        let child_id = child.base().0;
        _ = Box::into_raw(child);
        unsafe { simulo_add_object_child(self.0, child_id); }
    }

    pub fn position(&self) -> glam::Vec2 {
        unsafe { glam::Vec2::new(simulo_get_object_x(self.0), simulo_get_object_y(self.0)) }
    }

    pub fn set_position(&self, pos: glam::Vec2) {
        unsafe {
            simulo_set_object_position(self.0, pos.x, pos.y);
        }
    }

    pub fn rotation(&self) -> f32 {
        unsafe { simulo_get_object_rotation(self.0) }
    }

    pub fn set_rotation(&self, rotation: f32) {
        unsafe {
            simulo_set_object_rotation(self.0, rotation);
        }
    }

    pub fn get_scale(&self) -> glam::Vec2 {
        unsafe {
            glam::Vec2::new(
                simulo_get_object_scale_x(self.0),
                simulo_get_object_scale_y(self.0)
            )
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
            simulo_remove_object(self.0);
        }
    }
}

impl std::ops::Drop for BaseObject {
    fn drop(&mut self) {
        unsafe { simulo_drop_object(self.0); }
    }
}

pub struct Material(u32);

impl Material {
    pub fn new(image_id: u32, r: f32, g: f32, b: f32) -> Self {
        unsafe { Material(simulo_create_material(image_id, r, g, b)) }
    }

    pub fn delete(&self) {
        unsafe {
            simulo_delete_material(self.0);
        }
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
pub extern "C" fn init() {
    let g = crate::game::Game::new();
    unsafe {
        GAME = Box::leak(g);
        simulo_set_pose_buffer(POSE_DATA.as_mut_ptr());
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
    fn simulo_set_object_ptr(id: u32, type_hash: u32, ptr: *mut c_void);

    fn simulo_add_object_child(parent: u32, child: u32);

    fn simulo_set_object_position(id: u32, x: f32, y: f32);
    fn simulo_set_object_rotation(id: u32, rotation: f32);
    fn simulo_set_object_scale(id: u32, x: f32, y: f32);
    fn simulo_get_object_x(id: u32) -> f32;
    fn simulo_get_object_y(id: u32) -> f32;
    fn simulo_get_object_rotation(id: u32) -> f32;
    fn simulo_get_object_scale_x(id: u32) -> f32;
    fn simulo_get_object_scale_y(id: u32) -> f32;

    fn simulo_set_object_material(id: u32, material: u32);
    fn simulo_remove_object(id: u32);
    fn simulo_drop_object(id: u32);
    fn simulo_random() -> f32;
    fn simulo_window_width() -> i32;
    fn simulo_window_height() -> i32;
    fn simulo_create_material(image: u32, r: f32, g: f32, b: f32) -> u32;
    fn simulo_delete_material(id: u32);
}

/////////

mod game {
    use super::*;
    use glam::Vec2;

    #[ObjectClass]
    pub struct Game {
        obj: Option<GameObject>,
        mat: Option<Material>
    }

    impl Game {
        pub fn new() -> Box<Self> {
            BaseObject::new(Vec2::new(0.0, 0.0), &Material::new(WHITE_PIXEL_IMAGE, 1.0, 1.0, 1.0), |base| {
                return Game {
                    base,
                    mat: Material::new(WHITE_PIXEL_IMAGE, 1.0, 1.0, 1.0),
                }
            })
        }

        pub fn on_pose_update(&mut self, _id: u32, pose: Option<&Pose>) {
            if let Some(pose) = pose {
                let particle = BaseObject::new(pose.nose(), &self.mat, |obj| Particle {
                    base: obj,
                    lifetime: 1.0,
                    vel: Vec2::new(50.0, 50.0),
                });
                self.base.add_child(particle);
            }
        }
    }

    impl Object for Game {
        fn base(&self) -> &BaseObject {
            &self.base
        }
    }

    #[ObjectClass]
    struct Particle {
        base: BaseObject,
        lifetime: f32,
        vel: Vec2,
    }

    impl Object for Particle {
        fn base(&self) -> &BaseObject {
            &self.base
        }

        fn update(&mut self, delta: f32) {
            let pos = self.base.position();
            let dpos = self.vel * delta;
            self.base.set_position(pos + dpos);
            self.lifetime -= delta;
            if self.lifetime <= 0.0 {
                self.base.delete();
            }
        }
    }
}
