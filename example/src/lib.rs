mod game;
mod simulo;

static mut GAME: *mut game::Game = std::ptr::null_mut();

#[unsafe(no_mangle)]
pub extern "C" fn init(_root: u32) {
    let g = Box::new(game::Game::new());
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
