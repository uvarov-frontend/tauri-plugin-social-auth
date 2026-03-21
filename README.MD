# tauri-plugin-social-auth

Native social auth plugin for Tauri applications.

The plugin exposes one command surface for Apple, Google, VK ID, and Yandex, and delegates the actual sign-in flow to the native SDK available on the current platform.

What the plugin does:

- starts native provider auth
- returns normalized success payloads to JavaScript
- returns deterministic failures when native auth cannot be completed

What the plugin does not do:

- web OAuth
- browser fallback
- backend token exchange
- session management

Those parts belong to the application.

## Platform behavior

| Provider | iOS | macOS | Android | Web/Windows/Linux |
| --- | --- | --- | --- | --- |
| Apple | Native | Native | Unsupported | Unsupported |
| Google | Native | Unsupported | Native | Unsupported |
| VK ID | Native | Unsupported | Native | Unsupported |
| Yandex | Native | Unsupported | Native | Unsupported |

`Unsupported` means the command rejects with `SOCIAL_AUTH_UNSUPPORTED_PLATFORM`.

## Commands

- `plugin:social-auth|apple_sign_in`
- `plugin:social-auth|google_sign_in`
- `plugin:social-auth|vk_sign_in`
- `plugin:social-auth|yandex_sign_in`

## Success payloads

Apple:

```json
{
  "idToken": "...",
  "userIdentifier": "...",
  "authorizationCode": "...",
  "email": "user@example.com",
  "givenName": "John",
  "familyName": "Appleseed"
}
```

Google:

```json
{
  "idToken": "..."
}
```

VK ID:

```json
{
  "accessToken": "...",
  "deviceId": "..."
}
```

`deviceId` is returned by the iOS native VK flow and can be omitted on other platforms.

Yandex:

```json
{
  "accessToken": "..."
}
```

## Install

Add the Rust dependency:

```toml
[dependencies]
tauri-plugin-social-auth = "1.1"
```

Register the plugin in your Tauri app:

```rust
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_social_auth::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

Declare the plugin commands for Tauri capability generation in `src-tauri/build.rs`:

```rust
fn main() {
    tauri_build::try_build(
        tauri_build::Attributes::new().plugin(
            "social-auth",
            tauri_build::InlinedPlugin::new()
                .commands(&[
                    "apple_sign_in",
                    "google_sign_in",
                    "vk_sign_in",
                    "yandex_sign_in",
                ])
                .default_permission(tauri_build::DefaultPermissionRule::AllowAllCommands),
        ),
    )
    .expect("failed to run tauri-build");
}
```

Allow the plugin in your capability file:

```json
{
  "permissions": ["core:default", "social-auth:default"]
}
```

## JavaScript usage

```ts
import { invoke } from '@tauri-apps/api/core';

export async function signInWithApple() {
  return invoke<{
    idToken: string;
    userIdentifier: string;
    authorizationCode?: string;
    email?: string;
    givenName?: string;
    familyName?: string;
  }>('plugin:social-auth|apple_sign_in');
}

export async function signInWithGoogle() {
  return invoke<{ idToken: string }>('plugin:social-auth|google_sign_in');
}

export async function signInWithVk(theme?: 'light' | 'dark') {
  return invoke<{ accessToken: string; deviceId?: string }>(
    'plugin:social-auth|vk_sign_in',
    theme ? { theme } : undefined,
  );
}

export async function signInWithYandex() {
  return invoke<{ accessToken: string }>('plugin:social-auth|yandex_sign_in');
}
```

## iOS

On iOS the plugin uses native SDKs for Google, VK ID, Yandex, and Apple Sign-In.

The plugin expects these configuration values:

- `GOOGLE_SERVER_CLIENT_ID`
- `GOOGLE_IOS_CLIENT_ID`
- `VK_IOS_CLIENT_ID`
- `VK_IOS_CLIENT_SECRET`
- `YA_IOS_CLIENT_ID`

The plugin resolves them in this order:

1. `Info.plist`
2. `SocialAuthConfig.plist` from the app bundle

If you use `SocialAuthConfig.plist`, it must be present in the final app resources as `SocialAuthConfig.plist`.

The plugin also updates the generated iOS `Info.plist` during `tauri ios ...` builds so that:

- required URL schemes are present for Google, VK ID, and Yandex
- required `LSApplicationQueriesSchemes` entries are present for VK ID and Yandex

The app still must provide:

- `Sign in with Apple` capability
- entitlement `com.apple.developer.applesignin = ["Default"]`
- the provider config values listed above

At build time the plugin also:

- copies required SwiftPM `*.bundle` resources into the final iOS app
- re-signs embedded SwiftPM binaries for device builds when needed

## macOS

On macOS only `apple_sign_in` is implemented natively.

The app must provide:

- `Sign in with Apple` capability
- entitlement `com.apple.developer.applesignin = ["Default"]`

If your app uses this plugin on macOS, `src-tauri/build.rs` must also inject Swift runtime `rpath` entries into the final executable:

```rust
#[cfg(target_os = "macos")]
fn inject_swift_runtime_rpaths() {
    let mut runtime_paths = std::collections::BTreeSet::new();

    for (key, value) in std::env::vars() {
        if !key.starts_with("DEP_") || !key.ends_with("_SWIFT_RUNTIME_PATHS") {
            continue;
        }

        for path in value.split(';') {
            let path = path.trim();
            if !path.is_empty() {
                runtime_paths.insert(path.to_string());
            }
        }
    }

    for path in runtime_paths {
        println!("cargo:rustc-link-arg=-Wl,-rpath,{path}");
    }
}

fn main() {
    #[cfg(target_os = "macos")]
    inject_swift_runtime_rpaths();

    tauri_build::try_build(
        tauri_build::Attributes::new().plugin(
            "social-auth",
            tauri_build::InlinedPlugin::new()
                .commands(&[
                    "apple_sign_in",
                    "google_sign_in",
                    "vk_sign_in",
                    "yandex_sign_in",
                ])
                .default_permission(tauri_build::DefaultPermissionRule::AllowAllCommands),
        ),
    )
    .expect("failed to run tauri-build");
}
```

Important:

- Apple Sign-In on macOS must be tested with a signed `.app` bundle that actually carries the entitlement
- an unsigned `cargo run` / bare `target/debug/<app>` binary is not a valid test target for Apple Sign-In

## Android

On Android the plugin uses native Google, VK ID, and Yandex SDK flows.

The app must provide:

- `GOOGLE_SERVER_CLIENT_ID` in `BuildConfig`
- valid provider SDK setup for VK ID and Yandex in the Android project

`apple_sign_in` is intentionally unsupported on Android.

## Browser fallback

Browser fallback is intentionally outside the plugin.

The recommended application contract is:

- call the native plugin command first
- if native auth fails and your product allows fallback, start browser OAuth in the app layer
- complete the backend exchange in the app/backend layer exactly as you would for your web flow

This keeps native auth and web auth clearly separated.

## Error codes

Common:

- `SOCIAL_AUTH_UNSUPPORTED_PLATFORM`

Apple:

- `APPLE_AUTH_CANCELED`
- `APPLE_AUTH_FAILED`
- `APPLE_ID_TOKEN_EMPTY`

On macOS, `apple_sign_in` currently returns a human-readable bridge error string rather than a structured `code`.

Google:

- `GOOGLE_AUTH_CANCELED`
- `GOOGLE_SIGN_IN_INIT_FAILED`
- `GOOGLE_SIGN_IN_FAILED`
- `GOOGLE_TOKEN_PARSE_FAILED`
- `GOOGLE_ID_TOKEN_EMPTY`
- `GOOGLE_CREDENTIAL_MANAGER_FAILED`
- `GOOGLE_UNSUPPORTED_CREDENTIAL`
- `GOOGLE_AUTH_IOS_SDK_MISSING`

VK ID:

- `VK_AUTH_CANCELED`
- `VK_AUTH_INIT_FAILED`
- `VK_AUTH_FAILED`
- `VK_ACCESS_TOKEN_EMPTY`
- `VK_AUTH_IOS_SDK_MISSING`
- `VK_AUTH_IOS_URL_SCHEME_MISSING`

Yandex:

- `YANDEX_AUTH_CANCELED`
- `YANDEX_AUTH_INIT_FAILED`
- `YANDEX_AUTH_FAILED`
- `YANDEX_ACCESS_TOKEN_EMPTY`
- `YANDEX_AUTH_IOS_SDK_MISSING`
- `YANDEX_AUTH_IOS_URL_SCHEME_MISSING`

## Notes

- This plugin was fully developed with the help of AI.

## License

MIT or Apache-2.0.
