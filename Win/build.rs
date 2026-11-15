use std::{env, path::PathBuf, process::Command};

fn main() {
    println!("cargo:rerun-if-changed=resources/SnowVibe.rc");
    println!("cargo:rerun-if-changed=resources/SnowVibe.ico");
    println!("cargo:rerun-if-changed=resources/SnowVibe.manifest");
    println!("cargo:rerun-if-env-changed=RC");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    let source = PathBuf::from("resources/SnowVibe.rc");
    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let msvc = env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc");
    let resource = output.join(if msvc { "SnowVibe.res" } else { "SnowVibe.o" });
    let status = if msvc {
        Command::new("rc.exe")
            .arg("/nologo")
            .arg(format!("/fo{}", resource.display()))
            .arg(&source)
            .status()
    } else {
        Command::new(env::var("RC").unwrap_or_else(|_| "windres".into()))
            .arg(&source)
            .arg("-O")
            .arg("coff")
            .arg("-o")
            .arg(&resource)
            .status()
    };
    if !status.is_ok_and(|value| value.success()) {
        panic!("Windows resource compilation failed");
    }
    println!("cargo:rustc-link-arg-bin=snowvibe={}", resource.display());
}
