use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

#[cfg(target_os = "android")]
const SOCIAL_AUTH_PLUGIN_IDENTIFIER: &str = "app.tauri.socialauth";

#[cfg(target_os = "macos")]
mod macos;

#[cfg(target_os = "macos")]
mod models;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_social_auth);

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    #[allow(unused_mut)]
    let mut builder = Builder::new("social-auth");

    #[cfg(target_os = "macos")]
    {
        builder = builder.invoke_handler(tauri::generate_handler![
            macos::google_sign_in,
            macos::vk_sign_in,
            macos::yandex_sign_in,
            macos::apple_sign_in
        ]);
    }

    builder
        .setup(|_app, _api| {
            #[cfg(target_os = "android")]
            {
                let _ = _api
                    .register_android_plugin(SOCIAL_AUTH_PLUGIN_IDENTIFIER, "SocialAuthPlugin")?;
            }

            #[cfg(target_os = "ios")]
            {
                let _ = _api.register_ios_plugin(init_plugin_social_auth)?;
            }

            Ok(())
        })
        .build()
}
