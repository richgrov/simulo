use std::ffi::c_void;
use glam::{Mat4, Vec2};
use simulo_declare_type::ObjectClass;

pub trait ObjectClassed {
    const TYPE_ID: u32;
}

#[ObjectClass]
pub struct BaseObject {
    pub position: Vec2,
    pub rotation: f32,
    pub scale: Vec2,
    id: u32,
}

impl Object for BaseObject {
    fn base(&self) -> &BaseObject {
        self
    }

    fn recalculate_transform(&self) -> Mat4 {
        Mat4::from_translation(self.position.extend(0.0)) * Mat4::from_rotation_z(self.rotation) * Mat4::from_scale(self.scale.extend(1.0))
    }
}

pub trait Object {
    fn base(&self) -> &BaseObject;
    fn update(&mut self, _delta: f32) {}
    fn recalculate_transform(&self) -> Mat4;
}

#[allow(dead_code)]
impl BaseObject {
    pub fn new(material: &Material) -> Self {
        let id = unsafe { simulo_create_object(material.0) };
        Self {
            position: Vec2::ZERO,
            rotation: 0.0,
            scale: Vec2::ONE,
            id,
        }
    }

    pub fn add_child<T: Object + ObjectClassed + 'static>(&mut self, child: T) {
        let boxed = Box::new(child);
        let child_id = boxed.base().id;
        let ptr = Box::into_raw(boxed);
        let type_id = T::TYPE_ID;
        unsafe {
            simulo_set_object_ptr(child_id, type_id, ptr as *mut c_void);
            simulo_add_object_child(self.id, child_id);
        }
    }

    pub fn mark_transform_outdated(&self) {
        unsafe {
            simulo_mark_transform_outdated(self.id);
        }
    }

    pub fn set_material(&self, material: &Material) {
        unsafe {
            simulo_set_object_material(self.id, material.0);
        }
    }

    pub fn delete(&self) {
        unsafe {
            simulo_remove_object_from_parent(self.id);
        }
    }
}

impl std::ops::Drop for BaseObject {
    fn drop(&mut self) {
        unsafe { simulo_drop_object(self.id); }
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
static mut TRANSFORM_DATA: [f32; 16] = [0.0; 16];

#[unsafe(no_mangle)]
#[allow(static_mut_refs)]
pub extern "C" fn init() {
    let g = crate::game::Game::new();
    unsafe {
        let id = g.base().id;
        GAME = Box::leak(Box::new(g));
        simulo_set_buffers(POSE_DATA.as_mut_ptr(), TRANSFORM_DATA.as_mut_ptr());
        simulo_set_root(id, crate::game::Game::TYPE_ID, GAME as *mut c_void);
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
    fn simulo_set_root(id: u32, type_hash: u32, ptr: *mut c_void);
    fn simulo_set_buffers(pose: *mut f32, transform: *mut f32);

    fn simulo_create_object(material: u32) -> u32;
    fn simulo_set_object_ptr(id: u32, type_hash: u32, ptr: *mut c_void);
    fn simulo_add_object_child(parent: u32, child: u32);
    fn simulo_mark_transform_outdated(id: u32);

    fn simulo_set_object_material(id: u32, material: u32);
    fn simulo_remove_object_from_parent(id: u32);
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
        base: BaseObject,
        mat: Material,
    }

    impl Game {
        pub fn new() -> Self {
                Game {
                    base: BaseObject::new(&Material::new(WHITE_PIXEL_IMAGE, 1.0, 1.0, 1.0)),
                    mat: Material::new(WHITE_PIXEL_IMAGE, 1.0, 1.0, 1.0),
                }
        }

        pub fn on_pose_update(&mut self, _id: u32, pose: Option<&Pose>) {
            if let Some(pose) = pose {
                let mut particle = Particle {
                    base: BaseObject::new(&self.mat),
                    lifetime: 1.0,
                    vel: Vec2::new(50.0, 50.0),
                };
                particle.base.position = pose.nose();
                self.base.add_child(particle);
            }
        }
    }

    impl Object for Game {
        fn base(&self) -> &BaseObject {
            &self.base
        }

        fn recalculate_transform(&self) -> Mat4 {
            self.base.recalculate_transform()
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
            self.base.position += self.vel * delta;
            self.base.mark_transform_outdated();
            self.lifetime -= delta;
            if self.lifetime <= 0.0 {
                self.base.delete();
            }
        }

        fn recalculate_transform(&self) -> Mat4 {
            self.base.recalculate_transform()
        }
    }
}
