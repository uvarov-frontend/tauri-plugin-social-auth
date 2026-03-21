const COMMANDS: &[&str] = &[
    "google_sign_in",
    "vk_sign_in",
    "yandex_sign_in",
    "apple_sign_in",
];

fn file_content_hash(path: &std::path::Path) -> u64 {
    use std::hash::{Hash, Hasher};

    let bytes = std::fs::read(path)
        .unwrap_or_else(|error| panic!("failed to read {} for hashing: {error}", path.display()));
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    path.file_name().hash(&mut hasher);
    bytes.hash(&mut hasher);
    hasher.finish()
}

fn vk_captcha_stub_revision_key(source_dir: &std::path::Path) -> String {
    let package_swift = source_dir.join("Package.swift");
    let source_swift = source_dir
        .join("Sources")
        .join("VKCaptchaSDK")
        .join("VKCaptchaSDK.swift");

    format!(
        "{:016x}{:016x}",
        file_content_hash(&package_swift),
        file_content_hash(&source_swift)
    )
}

#[cfg(target_os = "macos")]
const SOCIAL_ENV_FILE_NAMES: &[&str] = &[
    ".env.development.local",
    ".env.local",
    ".env.development",
    ".env",
];

#[cfg(target_os = "macos")]
fn macos_swift_runtime_paths() -> Vec<std::path::PathBuf> {
    let swift_binary = find_swift_binary();
    let mut paths = Vec::new();

    if let Some(toolchain_usr_dir) = swift_binary.parent().and_then(std::path::Path::parent) {
        let toolchain_runtime = toolchain_usr_dir.join("lib").join("swift").join("macosx");
        if toolchain_runtime.exists() {
            paths.push(toolchain_runtime);
        }
    }

    let system_runtime = std::path::PathBuf::from("/usr/lib/swift");
    if system_runtime.exists() {
        paths.push(system_runtime);
    }

    paths.sort();
    paths.dedup();
    paths
}

#[cfg(target_os = "macos")]
fn emit_macos_swift_runtime_metadata() {
    if target_os().as_deref() != Some("macos") {
        return;
    }

    let paths = macos_swift_runtime_paths();
    if paths.is_empty() {
        return;
    }

    let encoded = paths
        .iter()
        .map(|path| path.display().to_string())
        .collect::<Vec<_>>()
        .join(";");

    println!("cargo:swift_runtime_paths={encoded}");
}

fn rerun_if_changed(path: &str) {
    println!("cargo:rerun-if-changed={path}");
}

fn target_os() -> Option<String> {
    std::env::var("CARGO_CFG_TARGET_OS").ok()
}

fn is_ios_build() -> bool {
    target_os().as_deref() == Some("ios")
}

fn is_ios_device_build() -> bool {
    target_os().as_deref() == Some("ios")
        && std::env::var("PLATFORM_NAME").as_deref() == Ok("iphoneos")
}

fn find_swift_binary() -> std::path::PathBuf {
    let output = std::process::Command::new("xcrun")
        .args(["--find", "swift"])
        .output();

    if let Ok(output) = output {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() {
                return std::path::PathBuf::from(path);
            }
        }
    }

    std::path::PathBuf::from("/usr/bin/swift")
}

fn sh_quote(value: &std::path::Path) -> String {
    let value = value.display().to_string();
    format!("'{}'", value.replace('\'', r"'\''"))
}

fn prepend_path(dir: &std::path::Path) {
    let current = std::env::var_os("PATH").unwrap_or_default();
    let mut paths = vec![dir.as_os_str().to_owned()];
    paths.extend(std::env::split_paths(&current).map(|path| path.into_os_string()));
    let joined = std::env::join_paths(paths).expect("failed to join PATH");
    std::env::set_var("PATH", joined);
}

fn copy_dir_recursive(from: &std::path::Path, to: &std::path::Path) {
    std::fs::create_dir_all(to)
        .unwrap_or_else(|error| panic!("failed to create dir {}: {error}", to.display()));

    for entry in std::fs::read_dir(from)
        .unwrap_or_else(|error| panic!("failed to read dir {}: {error}", from.display()))
    {
        let entry = entry.unwrap_or_else(|error| panic!("failed to read dir entry: {error}"));
        let entry_type = entry.file_type().unwrap_or_else(|error| {
            panic!(
                "failed to read file type for {}: {error}",
                entry.path().display()
            )
        });
        let from_path = entry.path();
        let to_path = to.join(entry.file_name());

        if entry_type.is_dir() {
            copy_dir_recursive(&from_path, &to_path);
            continue;
        }

        std::fs::copy(&from_path, &to_path).unwrap_or_else(|error| {
            panic!(
                "failed to copy {} to {}: {error}",
                from_path.display(),
                to_path.display()
            )
        });
    }
}

fn clear_dir_except_git(dir: &std::path::Path) {
    if !dir.exists() {
        return;
    }

    for entry in std::fs::read_dir(dir)
        .unwrap_or_else(|error| panic!("failed to read dir {}: {error}", dir.display()))
    {
        let entry = entry.unwrap_or_else(|error| panic!("failed to read dir entry: {error}"));
        let path = entry.path();

        if entry.file_name() == ".git" {
            continue;
        }

        if path.is_dir() {
            std::fs::remove_dir_all(&path)
                .unwrap_or_else(|error| panic!("failed to remove dir {}: {error}", path.display()));
        } else {
            std::fs::remove_file(&path).unwrap_or_else(|error| {
                panic!("failed to remove file {}: {error}", path.display())
            });
        }
    }
}

fn prepare_git_mirror(source_dir: &std::path::Path, mirror_dir: &std::path::Path) {
    let git_dir = mirror_dir.join(".git");

    if git_dir.exists() {
        clear_dir_except_git(mirror_dir);
    } else {
        std::fs::create_dir_all(mirror_dir).unwrap_or_else(|error| {
            panic!(
                "failed to create mirror dir {}: {error}",
                mirror_dir.display()
            )
        });
    }

    copy_dir_recursive(source_dir, mirror_dir);

    if !git_dir.exists() {
        let init_status = std::process::Command::new("git")
            .arg("init")
            .arg("-b")
            .arg("main")
            .arg(mirror_dir)
            .status()
            .unwrap_or_else(|error| {
                panic!(
                    "failed to initialize git mirror {}: {error}",
                    mirror_dir.display()
                )
            });
        if !init_status.success() {
            panic!("failed to initialize git mirror {}", mirror_dir.display());
        }
    }

    let add_status = std::process::Command::new("git")
        .arg("-C")
        .arg(mirror_dir)
        .args(["add", "."])
        .status()
        .unwrap_or_else(|error| {
            panic!(
                "failed to stage git mirror {}: {error}",
                mirror_dir.display()
            )
        });
    if !add_status.success() {
        panic!("failed to stage git mirror {}", mirror_dir.display());
    }

    let diff_status = std::process::Command::new("git")
        .arg("-C")
        .arg(mirror_dir)
        .args(["diff", "--cached", "--quiet", "--exit-code"])
        .status()
        .unwrap_or_else(|error| {
            panic!(
                "failed to diff git mirror {}: {error}",
                mirror_dir.display()
            )
        });
    if diff_status.success() {
        return;
    }

    let commit_status = std::process::Command::new("git")
        .arg("-C")
        .arg(mirror_dir)
        .args([
            "-c",
            "user.name=Codex",
            "-c",
            "user.email=codex@local.invalid",
            "commit",
            "-m",
            "VKCaptchaSDK stub",
            "--allow-empty",
        ])
        .status()
        .unwrap_or_else(|error| {
            panic!(
                "failed to commit git mirror {}: {error}",
                mirror_dir.display()
            )
        });
    if !commit_status.success() {
        panic!("failed to commit git mirror {}", mirror_dir.display());
    }

    let tag_status = std::process::Command::new("git")
        .arg("-C")
        .arg(mirror_dir)
        .args(["tag", "-f", "0.1.0"])
        .status()
        .unwrap_or_else(|error| {
            panic!("failed to tag git mirror {}: {error}", mirror_dir.display())
        });
    if !tag_status.success() {
        panic!("failed to tag git mirror {}", mirror_dir.display());
    }
}

fn install_ios_swift_wrapper() {
    use std::os::unix::fs::PermissionsExt;

    if !is_ios_build() {
        return;
    }

    let manifest_dir = std::path::PathBuf::from(
        std::env::var("CARGO_MANIFEST_DIR").expect("missing CARGO_MANIFEST_DIR"),
    );
    let ios_dir = manifest_dir.join("ios");
    let vk_captcha_stub_dir = ios_dir.join("VKCaptchaSDKStub");
    let out_dir =
        std::path::PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR for build.rs"));
    let swiftpm_config_dir = out_dir.join("swiftpm-config");
    let vk_captcha_mirror_dir = manifest_dir
        .join("target")
        .join("swiftpm-mirror")
        .join(format!(
            "vkcaptcha-sdk-mirror-{}",
            vk_captcha_stub_revision_key(&vk_captcha_stub_dir)
        ));
    let swift_wrapper_dir = out_dir.join("swift-bin");
    let swift_wrapper_path = swift_wrapper_dir.join("swift");
    let swift_binary = find_swift_binary();

    std::fs::create_dir_all(&swiftpm_config_dir).unwrap_or_else(|error| {
        panic!(
            "failed to create SwiftPM config dir {}: {error}",
            swiftpm_config_dir.display()
        )
    });
    std::fs::create_dir_all(&swift_wrapper_dir).unwrap_or_else(|error| {
        panic!(
            "failed to create Swift wrapper dir {}: {error}",
            swift_wrapper_dir.display()
        )
    });
    prepare_git_mirror(&vk_captcha_stub_dir, &vk_captcha_mirror_dir);

    let mirror_url = format!("file://{}", vk_captcha_mirror_dir.display());

    let mirror_status = std::process::Command::new(&swift_binary)
        .args(["package", "--package-path"])
        .arg(&ios_dir)
        .args(["--config-path"])
        .arg(&swiftpm_config_dir)
        .args([
            "config",
            "set-mirror",
            "--original",
            "https://github.com/VKCOM/vkid-captcha-ios-sdk",
            "--mirror",
        ])
        .arg(&mirror_url)
        .status()
        .unwrap_or_else(|error| panic!("failed to configure SwiftPM mirror: {error}"));

    if !mirror_status.success() {
        panic!(
            "failed to configure SwiftPM mirror for {}",
            vk_captcha_stub_dir.display()
        );
    }

    let wrapper_contents = format!(
        "#!/bin/sh\n\
set -eu\n\
if [ \"$#\" -gt 0 ]; then\n\
  case \"$1\" in\n\
    build|run|test|package|resolve|show-dependencies|clean|reset|update)\n\
      cmd=\"$1\"\n\
      shift\n\
      exec {swift} \"$cmd\" --config-path {config} \"$@\"\n\
      ;;\n\
  esac\n\
fi\n\
exec {swift} \"$@\"\n",
        swift = sh_quote(&swift_binary),
        config = sh_quote(&swiftpm_config_dir),
    );

    std::fs::write(&swift_wrapper_path, wrapper_contents).unwrap_or_else(|error| {
        panic!(
            "failed to write Swift wrapper {}: {error}",
            swift_wrapper_path.display()
        )
    });

    let mut permissions = std::fs::metadata(&swift_wrapper_path)
        .unwrap_or_else(|error| panic!("failed to read Swift wrapper metadata: {error}"))
        .permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&swift_wrapper_path, permissions)
        .unwrap_or_else(|error| panic!("failed to set Swift wrapper permissions: {error}"));

    prepend_path(&swift_wrapper_dir);

    println!(
        "cargo:warning=using SwiftPM mirror for VKCaptchaSDK from {}",
        vk_captcha_mirror_dir.display()
    );
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

fn collect_resource_bundles(root: &std::path::Path, bundles: &mut Vec<std::path::PathBuf>) {
    let Ok(entries) = std::fs::read_dir(root) else {
        return;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if path.extension().and_then(std::ffi::OsStr::to_str) == Some("bundle") {
                bundles.push(path);
                continue;
            }

            collect_resource_bundles(&path, bundles);
        }
    }
}

#[cfg(target_os = "macos")]
fn trim_env_value(value: &str) -> Option<String> {
    let trimmed = value
        .trim()
        .trim_matches('"')
        .trim_matches('\'')
        .trim()
        .to_string();
    (!trimmed.is_empty()).then_some(trimmed)
}

#[cfg(target_os = "macos")]
fn ios_project_path() -> Option<std::path::PathBuf> {
    std::env::var_os("TAURI_IOS_PROJECT_PATH").map(std::path::PathBuf::from)
}

#[cfg(target_os = "macos")]
fn social_env_candidate_files() -> Vec<std::path::PathBuf> {
    let mut files = Vec::new();

    if let Some(project_path) = ios_project_path() {
        for dir in project_path.ancestors() {
            for file_name in SOCIAL_ENV_FILE_NAMES {
                let path = dir.join(file_name);
                if path.exists() && !files.contains(&path) {
                    files.push(path);
                }
            }
        }
    }

    files
}

#[cfg(target_os = "macos")]
fn resolve_social_env_value(key: &str) -> Option<String> {
    println!("cargo:rerun-if-env-changed={key}");

    if let Ok(value) = std::env::var(key) {
        if let Some(value) = trim_env_value(&value) {
            return Some(value);
        }
    }

    for path in social_env_candidate_files() {
        println!("cargo:rerun-if-changed={}", path.display());
        let Ok(contents) = std::fs::read_to_string(&path) else {
            continue;
        };

        for line in contents.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            let Some((candidate_key, candidate_value)) = line.split_once('=') else {
                continue;
            };
            if candidate_key.trim() != key {
                continue;
            }

            if let Some(value) = trim_env_value(candidate_value) {
                return Some(value);
            }
        }
    }

    None
}

#[cfg(target_os = "macos")]
fn google_reversed_client_id(client_id: &str) -> Option<String> {
    client_id
        .strip_suffix(".apps.googleusercontent.com")
        .map(|prefix| format!("com.googleusercontent.apps.{prefix}"))
}

#[cfg(target_os = "macos")]
fn plist_string_array<'a>(dict: &'a mut plist::Dictionary, key: &str) -> &'a mut Vec<plist::Value> {
    if !matches!(dict.get(key), Some(plist::Value::Array(_))) {
        dict.insert(key.to_string(), plist::Value::Array(Vec::new()));
    }

    let value = dict.get_mut(key).expect("plist key must exist");

    match value {
        plist::Value::Array(values) => values,
        _ => unreachable!(),
    }
}

#[cfg(target_os = "macos")]
fn plist_array_contains_string(values: &[plist::Value], expected: &str) -> bool {
    values
        .iter()
        .any(|value| matches!(value, plist::Value::String(current) if current == expected))
}

#[cfg(target_os = "macos")]
fn ensure_plist_string(values: &mut Vec<plist::Value>, expected: String) {
    if !plist_array_contains_string(values, &expected) {
        values.push(plist::Value::String(expected));
    }
}

#[cfg(target_os = "macos")]
fn ensure_query_scheme(dict: &mut plist::Dictionary, scheme: String) {
    let values = plist_string_array(dict, "LSApplicationQueriesSchemes");
    ensure_plist_string(values, scheme);
}

#[cfg(target_os = "macos")]
fn ensure_url_scheme(dict: &mut plist::Dictionary, scheme: String) {
    let url_types = plist_string_array(dict, "CFBundleURLTypes");

    for value in url_types.iter_mut() {
        let plist::Value::Dictionary(entry) = value else {
            continue;
        };
        let schemes = plist_string_array(entry, "CFBundleURLSchemes");
        if plist_array_contains_string(schemes, &scheme) {
            return;
        }
    }

    let mut entry = plist::Dictionary::new();
    entry.insert(
        "CFBundleURLName".into(),
        plist::Value::String("social-auth".into()),
    );
    entry.insert(
        "CFBundleURLSchemes".into(),
        plist::Value::Array(vec![plist::Value::String(scheme)]),
    );
    url_types.push(plist::Value::Dictionary(entry));
}

#[cfg(target_os = "macos")]
fn sync_ios_social_auth_info_plist() {
    if !is_ios_build() {
        return;
    }

    let google_scheme = resolve_social_env_value("GOOGLE_IOS_CLIENT_ID")
        .and_then(|client_id| google_reversed_client_id(&client_id));
    let vk_scheme =
        resolve_social_env_value("VK_IOS_CLIENT_ID").map(|client_id| format!("vk{client_id}"));
    let yandex_scheme = resolve_social_env_value("YA_IOS_CLIENT_ID")
        .or_else(|| resolve_social_env_value("YA_CLIENT_ID"))
        .map(|client_id| format!("yx{client_id}"));

    let should_update = google_scheme.is_some() || vk_scheme.is_some() || yandex_scheme.is_some();
    if !should_update {
        return;
    }

    tauri_plugin::mobile::update_info_plist(|dict| {
        ensure_query_scheme(dict, "vkauthorize-silent".into());
        ensure_query_scheme(dict, "secondaryyandexloginsdk".into());
        ensure_query_scheme(dict, "primaryyandexloginsdk".into());

        if let Some(google_scheme) = google_scheme {
            ensure_url_scheme(dict, google_scheme);
        }

        if let Some(vk_scheme) = vk_scheme {
            ensure_url_scheme(dict, vk_scheme);
        }

        if let Some(yandex_scheme) = yandex_scheme {
            ensure_url_scheme(dict, yandex_scheme);
        }
    })
    .expect("failed to update iOS Info.plist for social auth");
}

#[cfg(not(target_os = "macos"))]
fn sync_ios_social_auth_info_plist() {}

fn prefer_resource_bundle(candidate: &std::path::Path, current: &std::path::Path) -> bool {
    let candidate_legacy = candidate
        .components()
        .any(|component| component.as_os_str() == "x86_64-apple-macosx");
    let current_legacy = current
        .components()
        .any(|component| component.as_os_str() == "x86_64-apple-macosx");

    if candidate_legacy != current_legacy {
        return !candidate_legacy;
    }

    candidate.components().count() < current.components().count()
}

fn copy_ios_resource_bundles() {
    if !is_ios_build() {
        return;
    }

    let Some(target_build_dir) = std::env::var_os("TARGET_BUILD_DIR") else {
        return;
    };
    let Some(resources_folder_path) = std::env::var_os("UNLOCALIZED_RESOURCES_FOLDER_PATH") else {
        return;
    };

    let out_dir =
        std::path::PathBuf::from(std::env::var("OUT_DIR").expect("missing OUT_DIR for build.rs"));
    let swift_output_dir = out_dir.join("swift-rs").join("tauri-plugin-social-auth");

    if !swift_output_dir.exists() {
        return;
    }

    let mut bundles = Vec::new();
    collect_resource_bundles(&swift_output_dir, &mut bundles);
    bundles.sort();
    let mut deduped = std::collections::BTreeMap::<std::ffi::OsString, std::path::PathBuf>::new();
    for bundle in bundles {
        let bundle_name = bundle
            .file_name()
            .expect("resource bundle must have a file name")
            .to_os_string();
        match deduped.get(&bundle_name) {
            Some(current) if !prefer_resource_bundle(&bundle, current) => {}
            _ => {
                deduped.insert(bundle_name, bundle);
            }
        }
    }

    if deduped.is_empty() {
        return;
    }

    let app_resources_dir = std::path::PathBuf::from(target_build_dir).join(resources_folder_path);
    std::fs::create_dir_all(&app_resources_dir).unwrap_or_else(|error| {
        panic!(
            "failed to create iOS app resources dir {}: {error}",
            app_resources_dir.display()
        )
    });

    for bundle in deduped.into_values() {
        let bundle_name = bundle
            .file_name()
            .expect("resource bundle must have a file name");
        let destination = app_resources_dir.join(bundle_name);

        if destination.exists() {
            std::fs::remove_dir_all(&destination).unwrap_or_else(|error| {
                panic!(
                    "failed to replace existing resource bundle {}: {error}",
                    destination.display()
                )
            });
        }

        copy_dir_recursive(&bundle, &destination);
        println!(
            "cargo:warning=copied iOS resource bundle {} -> {}",
            bundle.display(),
            destination.display()
        );
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
            .unwrap_or_else(|error| {
                panic!("failed to run codesign for {}: {error}", binary.display())
            });

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
    println!("cargo:rerun-if-env-changed=TARGET_BUILD_DIR");
    println!("cargo:rerun-if-env-changed=UNLOCALIZED_RESOURCES_FOLDER_PATH");
    rerun_if_changed("ios");
    rerun_if_changed("ios/VKCaptchaSDKStub");
    rerun_if_changed("android");
    rerun_if_changed("src");
    rerun_if_changed("build.rs");

    #[cfg(target_os = "macos")]
    emit_macos_swift_runtime_metadata();

    #[cfg(target_os = "macos")]
    link_macos_package();

    install_ios_swift_wrapper();
    sync_ios_social_auth_info_plist();

    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .ios_path("ios")
        .build();

    copy_ios_resource_bundles();
    resign_ios_embedded_binaries();
}
