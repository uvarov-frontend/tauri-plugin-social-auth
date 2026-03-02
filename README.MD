# tauri-plugin-social-auth

Native social sign-in plugin for Tauri mobile applications.

`tauri-plugin-social-auth` provides one Rust crate with three plugin commands:

- `plugin:google-auth|signIn` -> returns Google `idToken`
- `plugin:vk-auth|signIn` -> returns VK `accessToken`
- `plugin:yandex-auth|signIn` -> returns Yandex `accessToken`

| Platform | Supported |
| -------- | --------- |
| Linux    | -         |
| Windows  | -         |
| macOS    | -         |
| Android  | ✓         |
| iOS      | -         |

## Install

_This plugin requires Rust **1.77.2+**._

Add dependency in `src-tauri/Cargo.toml`:

```toml
[dependencies]
tauri-plugin-social-auth = "0.1"
```

## Setup

### 1. Register plugins in Rust

`src-tauri/src/lib.rs`:

```rust
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_social_auth::init_google_auth())
        .plugin(tauri_plugin_social_auth::init_vk_auth())
        .plugin(tauri_plugin_social_auth::init_yandex_auth())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### 2. Declare plugin commands for capability generation

`src-tauri/build.rs`:

```rust
fn main() {
    tauri_build::try_build(
        tauri_build::Attributes::new()
            .plugin(
                "google-auth",
                tauri_build::InlinedPlugin::new()
                    .commands(&["signIn"])
                    .default_permission(tauri_build::DefaultPermissionRule::AllowAllCommands),
            )
            .plugin(
                "vk-auth",
                tauri_build::InlinedPlugin::new()
                    .commands(&["signIn"])
                    .default_permission(tauri_build::DefaultPermissionRule::AllowAllCommands),
            )
            .plugin(
                "yandex-auth",
                tauri_build::InlinedPlugin::new()
                    .commands(&["signIn"])
                    .default_permission(tauri_build::DefaultPermissionRule::AllowAllCommands),
            ),
    )
    .expect("failed to run tauri-build");
}
```

### 3. Android configuration

- Min SDK: `26`.
- Set `GOOGLE_SERVER_CLIENT_ID` in app `BuildConfig` (used by Google Sign-In command).
- Plugin already declares `android.permission.INTERNET`.

Example (`android/app/build.gradle.kts`):

```kotlin
android {
  defaultConfig {
    val googleServerClientId = System.getenv("GOOGLE_SERVER_CLIENT_ID") ?: ""
    buildConfigField("String", "GOOGLE_SERVER_CLIENT_ID", "\"$googleServerClientId\"")
  }
}
```

## JavaScript usage

No separate guest JS package is required.

```ts
import { invoke } from "@tauri-apps/api/core";

export async function signInGoogle() {
  return invoke<{ idToken: string }>("plugin:google-auth|signIn");
}

export async function signInVk(theme?: "light" | "dark") {
  return invoke<{ accessToken: string }>("plugin:vk-auth|signIn", theme ? { theme } : undefined);
}

export async function signInYandex() {
  return invoke<{ accessToken: string }>("plugin:yandex-auth|signIn");
}
```

## Command contracts

Google:

- Command: `plugin:google-auth|signIn`
- Args: none
- Success: `{ idToken: string }`

VK:

- Command: `plugin:vk-auth|signIn`
- Args: `{ theme?: "light" | "dark" }`
- Success: `{ accessToken: string }`

Yandex:

- Command: `plugin:yandex-auth|signIn`
- Args: none
- Success: `{ accessToken: string }`

## Error codes

Canceled:

- `GOOGLE_AUTH_CANCELED`
- `VK_AUTH_CANCELED`
- `YANDEX_AUTH_CANCELED`

Init/config/runtime:

- `GOOGLE_SIGN_IN_INIT_FAILED`
- `VK_AUTH_INIT_FAILED`
- `YANDEX_AUTH_INIT_FAILED`
- `GOOGLE_SIGN_IN_FAILED`
- `VK_AUTH_FAILED`
- `YANDEX_AUTH_FAILED`

## Notes

This plugin was fully developed with the help of AI.

## License

MIT or Apache-2.0, where applicable.
