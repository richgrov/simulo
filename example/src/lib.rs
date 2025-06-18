mod game;
mod simulo;

#[unsafe(no_mangle)]
pub extern "C" fn init(_root: u32) {
    game::start();
}
