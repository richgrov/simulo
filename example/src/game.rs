use crate::simulo::*;

pub struct Game {
    obj: GameObject,
}

impl Game {
    pub fn new() -> Self {
        let mut obj = GameObject::new(500.0, 500.0);
        obj.set_scale(100.0, 100.0);
        Game { obj }
    }

    pub fn update(&mut self, _delta: f32) {}

    pub fn on_pose_update(&mut self, id: u32, x: f32, y: f32) {
        if x == -1.0 && y == -1.0 {
            return;
        }
        self.obj.set_position(x, y);
    }
}
