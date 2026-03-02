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

pub fn init_google_auth<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("google-auth")
        .setup(|_app, _api| {
            #[cfg(target_os = "android")]
            {
                let _ =
                    _api.register_android_plugin(GOOGLE_PLUGIN_IDENTIFIER, "GoogleAuthPlugin")?;
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
            Ok(())
        })
        .build()
}

pub fn init_yandex_auth<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("yandex-auth")
        .setup(|_app, _api| {
            #[cfg(target_os = "android")]
            {
                let _ =
                    _api.register_android_plugin(YANDEX_PLUGIN_IDENTIFIER, "YandexAuthPlugin")?;
            }
            Ok(())
        })
        .build()
}
