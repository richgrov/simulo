use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, DeriveInput};

#[proc_macro_attribute]
#[allow(non_snake_case)]
pub fn ObjectClass(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as DeriveInput);
    let struct_name = input.ident.clone();
    
    let name_string = struct_name.to_string();
    let hash = generate_hash(&name_string);
    let hash_str = hash.to_string();
    
    let output = quote! {
        #input
        
        impl ObjectClassed for #struct_name {
            const TYPE_ID: u32 = #hash;
        }
        
        paste::paste! {
            #[unsafe(no_mangle)]
            pub extern "C" fn [< __vupdate_ #hash_str >](concrete_this: *mut std::ffi::c_void, delta: f32) {
                let ptr = concrete_this as *mut #struct_name;
                let obj = unsafe { &mut *ptr };
                obj.update(delta);
            }

            #[unsafe(no_mangle)]
            pub extern "C" fn [< __vrecalculate_transform_ #hash_str >](concrete_this: *mut std::ffi::c_void) {
                let ptr = concrete_this as *mut #struct_name;
                let obj = unsafe { &mut *ptr };
                let transform = obj.recalculate_transform();
                unsafe {
                    TRANSFORM_DATA = transform.to_cols_array();
                }
            }

            #[unsafe(no_mangle)]
            pub extern "C" fn [< __vdrop_ #hash_str >](dyn_this: *mut std::ffi::c_void) {
                let ptr = dyn_this as *mut std::boxed::Box<dyn Object>;
                unsafe { drop(std::boxed::Box::from_raw(ptr)); }
            }
        }
    };
    
    output.into()
}

fn generate_hash(s: &str) -> u32 {
    let mut hash: u32 = 0x811c9dc5; // FNV-1a offset basis
    for byte in s.bytes() {
        hash ^= byte as u32;
        hash = hash.wrapping_mul(0x01000193); // FNV-1a prime
    }
    hash
}
