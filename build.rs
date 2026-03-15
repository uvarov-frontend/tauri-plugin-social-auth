const COMMANDS: &[&str] = &[
    "google_sign_in",
    "vk_sign_in",
    "yandex_sign_in",
    "apple_sign_in",
];

fn target_os() -> Option<String> {
    std::env::var("CARGO_CFG_TARGET_OS").ok()
}

fn is_ios_device_build() -> bool {
    target_os().as_deref() == Some("ios")
        && std::env::var("PLATFORM_NAME").as_deref() == Ok("iphoneos")
}

fn expanded_code_sign_identity() -> Option<String> {
    std::env::var("EXPANDED_CODE_SIGN_IDENTITY")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty() && value != "-")
}

fn collect_embedded_binaries(root: &std::path::Path, binaries: &mut Vec<std::path::PathBuf>) {
    let Ok(entries) = std::fs::read_dir(root) else {
        return;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if path.extension().and_then(std::ffi::OsStr::to_str) == Some("framework") {
                binaries.push(path);
                continue;
            }

            collect_embedded_binaries(&path, binaries);
            continue;
        }

        if path.extension().and_then(std::ffi::OsStr::to_str) == Some("dylib") {
            binaries.push(path);
        }
    }
}

fn resign_ios_embedded_binaries() {
    if !is_ios_device_build() {
        return;
    }

    let Some(identity) = expanded_code_sign_identity() else {
        return;
    };

    let out_dir =
        std::path::PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR for build.rs"));
    let swift_output_dir = out_dir.join("swift-rs").join("tauri-plugin-social-auth");

    if !swift_output_dir.exists() {
        return;
    }

    let mut binaries = Vec::new();
    collect_embedded_binaries(&swift_output_dir, &mut binaries);
    binaries.sort();
    binaries.dedup();

    for binary in binaries {
        let status = std::process::Command::new("/usr/bin/codesign")
            .arg("--force")
            .arg("--sign")
            .arg(&identity)
            .arg("--timestamp=none")
            .arg("--preserve-metadata=identifier,flags")
            .arg(&binary)
            .status()
            .unwrap_or_else(|error| panic!("failed to run codesign for {}: {error}", binary.display()));

        if !status.success() {
            panic!("failed to re-sign embedded binary {}", binary.display());
        }

        println!("cargo:warning=re-signed {}", binary.display());
    }
}

#[cfg(target_os = "macos")]
fn link_macos_package() {
    use std::path::PathBuf;

    if target_os().as_deref() != Some("macos") {
        return;
    }

    let manifest_dir =
        PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("missing CARGO_MANIFEST_DIR"));
    let package_dir = manifest_dir.join("macos");
    let sdk_root = std::env::var_os("SDKROOT");

    std::env::remove_var("SDKROOT");
    swift_rs::SwiftLinker::new("12.0")
        .with_ios("15.0")
        .with_package("SocialAuthMacOS", &package_dir)
        .link();
    if let Some(root) = sdk_root {
        std::env::set_var("SDKROOT", root);
    }

    println!("cargo:rerun-if-changed={}", package_dir.display());
}

fn main() {
    println!("cargo:rerun-if-env-changed=EXPANDED_CODE_SIGN_IDENTITY");
    println!("cargo:rerun-if-env-changed=PLATFORM_NAME");

    #[cfg(target_os = "macos")]
    link_macos_package();

    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .ios_path("ios")
        .build();

    resign_ios_embedded_binaries();
}
