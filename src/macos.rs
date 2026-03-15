use serde::de::DeserializeOwned;
use swift_rs::{swift, SRString};
use tauri::async_runtime::spawn_blocking;

use crate::models::{AppleSignInPayload, SocialAccessTokenPayload, SocialIdTokenPayload};

swift!(fn social_auth_macos_apple_sign_in() -> SRString);

#[derive(Debug, serde::Deserialize)]
#[serde(untagged)]
enum BridgeResponse<T> {
    Success { data: T },
    Error { error: String },
}

fn decode_response<T: DeserializeOwned>(response: SRString) -> Result<T, String> {
    let raw = response.as_str();
    let parsed: BridgeResponse<T> = serde_json::from_str(raw)
        .map_err(|error| format!("invalid macOS bridge response: {error}"))?;

    match parsed {
        BridgeResponse::Success { data } => Ok(data),
        BridgeResponse::Error { error } => Err(error),
    }
}

fn invoke_without_payload<T>(call: unsafe fn() -> SRString) -> Result<T, String>
where
    T: DeserializeOwned,
{
    decode_response(unsafe { call() })
}

async fn run_blocking<T, F>(work: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, String> + Send + 'static,
{
    spawn_blocking(work)
        .await
        .map_err(|error| format!("failed to join macOS social auth task: {error}"))?
}

fn unsupported_platform(provider: &str) -> String {
    format!("SOCIAL_AUTH_UNSUPPORTED_PLATFORM: native {provider} auth is not supported on macOS")
}

#[tauri::command]
pub async fn google_sign_in() -> Result<SocialIdTokenPayload, String> {
    Err(unsupported_platform("Google"))
}

#[tauri::command]
pub async fn vk_sign_in() -> Result<SocialAccessTokenPayload, String> {
    Err(unsupported_platform("VK"))
}

#[tauri::command]
pub async fn yandex_sign_in() -> Result<SocialAccessTokenPayload, String> {
    Err(unsupported_platform("Yandex"))
}

#[tauri::command]
pub async fn apple_sign_in() -> Result<AppleSignInPayload, String> {
    run_blocking(|| invoke_without_payload(social_auth_macos_apple_sign_in)).await
}
