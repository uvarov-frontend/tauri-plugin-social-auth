use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

#[cfg(target_os = "android")]
const GOOGLE_PLUGIN_IDENTIFIER: &str = "app.tauri.socialauth.google";
#[cfg(target_os = "android")]
const VK_PLUGIN_IDENTIFIER: &str = "app.tauri.socialauth.vk";
#[cfg(target_os = "android")]
const YANDEX_PLUGIN_IDENTIFIER: &str = "app.tauri.socialauth.yandex";

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_google_auth);
#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_vk_auth);
#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_yandex_auth);

pub fn init_google_auth<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("google-auth")
        .setup(|_app, _api| {
            #[cfg(target_os = "android")]
            {
                let _ = _api.register_android_plugin(GOOGLE_PLUGIN_IDENTIFIER, "GoogleAuthPlugin")?;
            }
            #[cfg(target_os = "ios")]
            {
                let _ = _api.register_ios_plugin(init_plugin_google_auth)?;
            }
            Ok(())
        })
        .build()
}

pub fn init_vk_auth<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("vk-auth")
        .setup(|_app, _api| {
            #[cfg(target_os = "android")]
            {
                let _ = _api.register_android_plugin(VK_PLUGIN_IDENTIFIER, "VkAuthPlugin")?;
            }
            #[cfg(target_os = "ios")]
            {
                let _ = _api.register_ios_plugin(init_plugin_vk_auth)?;
            }
            Ok(())
        })
        .build()
}

pub fn init_yandex_auth<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("yandex-auth")
        .setup(|_app, _api| {
            #[cfg(target_os = "android")]
            {
                let _ = _api.register_android_plugin(YANDEX_PLUGIN_IDENTIFIER, "YandexAuthPlugin")?;
            }
            #[cfg(target_os = "ios")]
            {
                let _ = _api.register_ios_plugin(init_plugin_yandex_auth)?;
            }
            Ok(())
        })
        .build()
}
