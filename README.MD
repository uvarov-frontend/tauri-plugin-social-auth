# tauri-plugin-social-auth

Native social auth plugin for Tauri applications with a single unified command surface.

## Platform matrix

| Provider | iOS | macOS | Android | Web |
| --- | --- | --- | --- | --- |
| Apple | Native | Native | Unsupported | Unsupported |
| Google | Native | Unsupported | Native | Unsupported |
| VK ID | Native | Unsupported | Native | Unsupported |
| Yandex | Native | Unsupported | Native | Unsupported |

Notes:

- `Unsupported` means the plugin command rejects with `SOCIAL_AUTH_UNSUPPORTED_PLATFORM`.
- Browser fallback is an application concern. This plugin only performs native auth and returns deterministic success or failure.

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
  "accessToken": "..."
}
```

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
tauri-plugin-social-auth = "1"
```

Register the plugin:

```rust
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_social_auth::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

Declare commands for capability generation in `src-tauri/build.rs`:

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

Allow the default permission set in your capability file:

```json
{
  "permissions": ["core:default", "social-auth:default"]
}
```

## Configuration

### iOS

The plugin reads provider configuration from `SocialAuthConfig.plist`.

Expected keys:

- `GOOGLE_SERVER_CLIENT_ID`
- `GOOGLE_IOS_CLIENT_ID`
- `VK_IOS_CLIENT_ID`
- `VK_IOS_CLIENT_SECRET`
- `YA_IOS_CLIENT_ID`

You also need:

- Apple capability `Sign in with Apple`
- entitlement `com.apple.developer.applesignin = ["Default"]`
- URL schemes for Google, VK ID, and Yandex if you use those SDKs
- `LSApplicationQueriesSchemes` entries required by the linked provider SDKs

### macOS

Only `apple_sign_in` is implemented natively on macOS.

You need:

- Apple capability `Sign in with Apple`
- entitlement `com.apple.developer.applesignin = ["Default"]`

### Android

Expected app configuration:

- `GOOGLE_SERVER_CLIENT_ID` in `BuildConfig`
- current VK ID and Yandex SDK setup used by your app

`apple_sign_in` is intentionally unsupported on Android.

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
  return invoke<{ accessToken: string }>('plugin:social-auth|vk_sign_in', theme ? { theme } : undefined);
}

export async function signInWithYandex() {
  return invoke<{ accessToken: string }>('plugin:social-auth|yandex_sign_in');
}
```

## Error codes

Common:

- `SOCIAL_AUTH_UNSUPPORTED_PLATFORM`

Apple:

- `APPLE_AUTH_CANCELED`
- `APPLE_AUTH_FAILED`
- `APPLE_ID_TOKEN_EMPTY`

Google:

- `GOOGLE_AUTH_CANCELED`
- `GOOGLE_SIGN_IN_INIT_FAILED`
- `GOOGLE_SIGN_IN_FAILED`
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
- iOS and macOS native bridges are implemented in Swift.
- Android keeps native SDK flows for Google, VK ID, and Yandex.
- macOS intentionally exposes only Apple Sign-In natively.

## License

MIT or Apache-2.0.
