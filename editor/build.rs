use std::path::Path;
use std::path::PathBuf;

fn main() -> miette::Result<()> {
    println!("cargo:rustc-link-search=build/macos-debug/src");
    println!("cargo:rustc-link-lib=simulo_common");
    println!("cargo:rustc-link-lib=framework=Foundation");
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=Metal");
    println!("cargo:rustc-link-lib=framework=QuartzCore");
    let include_path = std::path::PathBuf::from("../src");

    let mut b = autocxx_build::Builder::new("src/simulo_cc.rs", &[&include_path])
        .extra_clang_args(&["-std=c++20", "-stdlib=libc++"])
        .build()?;

    b.flag_if_supported("-std=c++20").compile("autocxx-demo");

    println!("cargo:rerun-if-changed=src/simulo_cc.rs");

    let vulkan_shaders = [
        "shader/text.vert",
        "shader/text.frag",
        "shader/model.vert",
        "shader/model.frag",
    ];

    for file in vulkan_shaders {
        println!("cargo:rerun-if-changed={}", file);
        let array_name = file.replace("/", "_").replace(".", "_");
        let file_name = std::path::Path::new(file)
            .file_name()
            .unwrap()
            .to_string_lossy();

        let output_path = std::path::PathBuf::from("res").join(format!("{}.h", file_name));
        std::process::Command::new("bash")
            .arg("-c")
            .arg(format!(
                "glslc {} -o - | xxd -i -n {} > {}",
                file,
                array_name,
                output_path.display()
            ))
            .status()
            .unwrap();
    }

    let metal_files = ["../src/shader/text.metal"];
    for file in metal_files {
        println!("cargo:rerun-if-changed={}", file);
        let file_name = Path::new(file).file_stem().unwrap().to_string_lossy();
        let air_path = PathBuf::from(format!("{}.air", file_name));
        std::process::Command::new("bash")
            .arg("-c")
            .arg(format!(
                "xcrun -sdk macosx metal -c {} -o {}",
                file,
                air_path.display()
            ))
            .status()
            .expect("Failed to compile metal shader");
        std::process::Command::new("bash")
            .arg("-c")
            .arg(format!(
                "xcrun -sdk macosx metallib {} -o {}",
                air_path.display(),
                "../default.metallib"
            ))
            .status()
            .expect("Failed to link metallib");
    }

    Ok(())
}
