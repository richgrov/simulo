//! Documentation for Simulo: the game engine of the real world. All APIs are available in the
//! global namespace.
//!
//! A struct `Game` must be declared with the following functions:
//! ```rust
//! pub struct Game {
//!     // ...
//! }
//!
//! impl Game {
//!     pub fn new() -> Self {
//!         // ...
//!     }
//!
//!     pub fn update(&mut self, delta: f32) {
//!         // ...
//!     }
//! }
//! ```
//!
//! Coordinate system:
//! +X = left
//! +Y = up
//! +Z = forward

/// A lightweight handle to an object in the scene. If dropped, the object will still exist. If
/// deleted with `GameObject::delete()`, the object will be removed from the scene and all copies
/// of this object will be invalid.
///
/// The object's position describes the top-left corner of the it's bounding box.
pub struct GameObject(u32);

#[allow(dead_code)]
impl GameObject {
    /// Creates and spawns a new object at the given viewport position. It starts at a 1x1 pixel scale.
    pub fn new(x: f32, y: f32) -> Self {
        let id = unsafe { simulo_create_object(x, y) };
        GameObject(id)
    }

    /// Sets the position of the object in the viewport.
    pub fn set_position(&self, x: f32, y: f32) {
        unsafe {
            simulo_set_object_position(self.0, x, y);
        }
    }

    /// Sets the scale of the object in the viewport.
    pub fn set_scale(&self, x: f32, y: f32) {
        unsafe {
            simulo_set_object_scale(self.0, x, y);
        }
    }

    /// Deletes the object from the scene. If this object handle was cloned, all other instances are
    /// also invalid. They may point to nothing, or a different object.
    pub fn delete(&self) {
        unsafe {
            simulo_delete_object(self.0);
        }
    }
}

unsafe extern "C" {
    fn simulo_create_object(x: f32, y: f32) -> u32;
    fn simulo_set_object_position(id: u32, x: f32, y: f32);
    fn simulo_set_object_scale(id: u32, x: f32, y: f32);
    fn simulo_delete_object(id: u32);
}
