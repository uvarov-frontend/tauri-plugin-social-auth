package app.tauri.socialauth.yandex

import android.app.Activity
import androidx.activity.result.ActivityResult
import app.tauri.Logger
import app.tauri.annotation.ActivityCallback
import app.tauri.annotation.Command
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import com.yandex.authsdk.YandexAuthLoginOptions
import com.yandex.authsdk.YandexAuthOptions
import com.yandex.authsdk.YandexAuthResult
import com.yandex.authsdk.YandexAuthSdk

@TauriPlugin
class YandexAuthPlugin(private val activity: Activity) : Plugin(activity) {
    private val yandexAuthSdk: YandexAuthSdk by lazy {
        YandexAuthSdk.create(YandexAuthOptions(activity.applicationContext))
    }

    @Command
    fun signIn(invoke: Invoke) {
        try {
            val intent = yandexAuthSdk.contract.createIntent(activity, YandexAuthLoginOptions())
            startActivityForResult(invoke, intent, "onYandexSignInResult")
        } catch (error: Exception) {
            invoke.reject("Yandex Sign-In initialization failed", "YANDEX_AUTH_INIT_FAILED", error)
        }
    }

    @ActivityCallback
    fun onYandexSignInResult(invoke: Invoke, result: ActivityResult) {
        try {
            val authResult = yandexAuthSdk.contract.parseResult(result.resultCode, result.data)
            when (authResult) {
                is YandexAuthResult.Success -> {
                    val accessToken = authResult.token.value
                    if (accessToken.isBlank()) {
                        invoke.reject("Yandex Sign-In failed: access token is empty", "YANDEX_ACCESS_TOKEN_EMPTY")
                        return
                    }

                    val data = JSObject()
                    data.put("accessToken", accessToken)
                    invoke.resolve(data)
                }

                is YandexAuthResult.Cancelled -> {
                    invoke.reject("Yandex Sign-In canceled by user", "YANDEX_AUTH_CANCELED")
                }

                is YandexAuthResult.Failure -> {
                    Logger.error(
                        Logger.tags("YandexAuth"),
                        "Yandex Sign-In failed: ${authResult.exception.message}",
                        authResult.exception,
                    )
                    invoke.reject("Yandex Sign-In failed", "YANDEX_AUTH_FAILED", authResult.exception)
                }
            }
        } catch (error: Exception) {
            invoke.reject("Yandex Sign-In failed", "YANDEX_AUTH_FAILED", error)
        }
    }
}
