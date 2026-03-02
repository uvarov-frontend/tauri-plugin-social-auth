# tauri-plugin-social-auth

Native social sign-in plugin for Tauri mobile applications.

`tauri-plugin-social-auth` provides one Rust plugin crate with three Tauri plugins:

- `google-auth` -> returns Google `idToken`
- `vk-auth` -> returns VK `accessToken`
- `yandex-auth` -> returns Yandex `accessToken`

| Platform | Supported |
| -------- | --------- |
| Linux    | -         |
| Windows  | -         |
| macOS    | -         |
| Android  | ✓         |
| iOS      | ✓         |

## Install

_This plugin requires a Rust version of at least **1.77.2**._

Add dependency in `src-tauri/Cargo.toml`:

```toml
[dependencies]
tauri-plugin-social-auth = "0.1"
# or from Git:
# tauri-plugin-social-auth = { git = "https://github.com/uvarov-frontend/tauri-plugin-social-auth", tag = "v0.1.0" }
```

## Setting up

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

Because this crate exposes three plugin names, add them in `src-tauri/build.rs`:

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

Then enable permissions in your capability file (example `src-tauri/capabilities/default.json`):

```json
{
  "identifier": "default",
  "description": "Default capability",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "google-auth:default",
    "vk-auth:default",
    "yandex-auth:default"
  ]
}
```

### 3. Platform configuration

Android:

- Min SDK: 26.
- Ensure app `BuildConfig` contains `GOOGLE_SERVER_CLIENT_ID` (used by Google Sign-In command).
- The plugin already declares `android.permission.INTERNET`.

Example in app module `build.gradle.kts`:

```kotlin
android {
  defaultConfig {
    val googleServerClientId = System.getenv("GOOGLE_SERVER_CLIENT_ID") ?: ""
    buildConfigField("String", "GOOGLE_SERVER_CLIENT_ID", "\"$googleServerClientId\"")
  }
}
```

iOS:

Provide social config keys either in `Info.plist` or in bundled `SocialAuthConfig.plist`:

- `GOOGLE_SERVER_CLIENT_ID`
- `GOOGLE_IOS_CLIENT_ID`
- `VK_IOS_CLIENT_ID`
- `VK_IOS_CLIENT_SECRET`
- `YA_IOS_CLIENT_ID`

Required iOS URL/query schemes:

- VK: `LSApplicationQueriesSchemes` must contain `vkauthorize-silent`
- VK: `CFBundleURLTypes` must contain `vk<VK_IOS_CLIENT_ID>`
- Yandex: `CFBundleURLTypes` must contain `yx<YA_IOS_CLIENT_ID>`
- Google: add reversed iOS client id URL scheme from your Google iOS OAuth client

Example `Info.plist` entries (copy-paste baseline):

```xml
<key>GOOGLE_SERVER_CLIENT_ID</key>
<string>YOUR_WEB_CLIENT_ID.apps.googleusercontent.com</string>
<key>GOOGLE_IOS_CLIENT_ID</key>
<string>YOUR_IOS_CLIENT_ID.apps.googleusercontent.com</string>
<key>VK_IOS_CLIENT_ID</key>
<string>YOUR_VK_APP_ID</string>
<key>VK_IOS_CLIENT_SECRET</key>
<string>YOUR_VK_SECURE_KEY</string>
<key>YA_IOS_CLIENT_ID</key>
<string>YOUR_YANDEX_CLIENT_ID</string>

<key>LSApplicationQueriesSchemes</key>
<array>
  <string>vkauthorize-silent</string>
</array>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>google</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_REVERSED_IOS_CLIENT_ID</string>
    </array>
  </dict>
  <dict>
    <key>CFBundleURLName</key>
    <string>vk</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>vkYOUR_VK_APP_ID</string>
    </array>
  </dict>
  <dict>
    <key>CFBundleURLName</key>
    <string>yandex</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>yxYOUR_YANDEX_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

If you prefer secrets outside `Info.plist`, bundle `SocialAuthConfig.plist` with the same keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>GOOGLE_SERVER_CLIENT_ID</key>
  <string>...</string>
  <key>GOOGLE_IOS_CLIENT_ID</key>
  <string>...</string>
  <key>VK_IOS_CLIENT_ID</key>
  <string>...</string>
  <key>VK_IOS_CLIENT_SECRET</key>
  <string>...</string>
  <key>YA_IOS_CLIENT_ID</key>
  <string>...</string>
</dict>
</plist>
```

VK-specific note:

- No extra Swift/AppDelegate glue is required for this plugin.
- Current iOS VK flow uses `forceWebViewFlow: true`, so Universal Links are not required by the plugin itself.

## JavaScript usage

No separate guest JS package is required.

Use `invoke` from `@tauri-apps/api/core` directly:

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

Common user-cancel flow:

- Google: `GOOGLE_AUTH_CANCELED`
- VK: `VK_AUTH_CANCELED`
- Yandex: `YANDEX_AUTH_CANCELED`

Initialization/config issues:

- Google: `GOOGLE_SIGN_IN_INIT_FAILED`
- VK: `VK_AUTH_INIT_FAILED`
- Yandex: `YANDEX_AUTH_INIT_FAILED`

SDK/platform specific:

- Google iOS SDK missing: `GOOGLE_AUTH_IOS_SDK_MISSING`
- VK iOS SDK missing: `VK_AUTH_IOS_SDK_MISSING`
- Yandex iOS SDK missing: `YANDEX_AUTH_IOS_SDK_MISSING`
- VK iOS URL/query scheme missing: `VK_AUTH_IOS_URL_SCHEME_MISSING`
- Yandex iOS URL scheme missing: `YANDEX_AUTH_IOS_URL_SCHEME_MISSING`

## Notes

- This plugin was fully developed with the help of AI.
- This crate targets mobile auth flows only.
- Tokens returned by this plugin should be verified/exchanged on your backend according to provider requirements.

## License

MIT or Apache-2.0, where applicable.
