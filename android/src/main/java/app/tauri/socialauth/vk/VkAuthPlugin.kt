package app.tauri.socialauth.vk

import android.app.Activity
import android.content.res.Configuration
import androidx.lifecycle.LifecycleOwner
import app.tauri.Logger
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import com.vk.id.AccessToken
import com.vk.id.VKID
import com.vk.id.VKIDAuthFail
import com.vk.id.auth.VKIDAuthCallback
import com.vk.id.auth.VKIDAuthParams

@InvokeArg
class VkSignInArgs {
    var theme: String? = null
}

@TauriPlugin
class VkAuthPlugin(private val activity: Activity) : Plugin(activity) {
    companion object {
        @Volatile
        private var vkIdInitialized = false
    }

    @Command
    fun signIn(invoke: Invoke) {
        val lifecycleOwner = activity as? LifecycleOwner
        if (lifecycleOwner == null) {
            invoke.reject("VK ID Sign-In failed: activity is not LifecycleOwner", "VK_AUTH_INIT_FAILED")
            return
        }

        val args = runCatching { invoke.parseArgs(VkSignInArgs::class.java) }.getOrNull()
        val preferredTheme = args?.theme?.trim()?.lowercase()

        try {
            ensureVkIdInitialized()

            val authParamsBuilder = VKIDAuthParams.Builder()
            authParamsBuilder.theme = resolveTheme(preferredTheme)
            authParamsBuilder.scopes = setOf("vkid.personal_info", "email", "user_id")
            val authParams = authParamsBuilder.build()

            VKID.instance.authorize(
                lifecycleOwner = lifecycleOwner,
                params = authParams,
                callback =
                    object : VKIDAuthCallback {
                        override fun onAuth(accessToken: AccessToken) {
                            val token = accessToken.token
                            if (token.isNullOrBlank()) {
                                invoke.reject("VK ID Sign-In failed: access token is empty", "VK_ACCESS_TOKEN_EMPTY")
                                return
                            }

                            val data = JSObject()
                            data.put("accessToken", token)
                            invoke.resolve(data)
                        }

                        override fun onFail(fail: VKIDAuthFail) {
                            if (fail is VKIDAuthFail.Canceled) {
                                invoke.reject("VK ID Sign-In canceled by user", "VK_AUTH_CANCELED")
                                return
                            }

                            val details = "package=${activity.packageName}, fail=${fail::class.simpleName}"
                            Logger.error(Logger.tags("VkAuth"), "VK ID sign-in failed: $details", null)
                            invoke.reject("VK ID Sign-In failed ($details)", "VK_AUTH_FAILED")
                        }
                    },
            )
        } catch (error: Exception) {
            invoke.reject("VK ID Sign-In initialization failed", "VK_AUTH_INIT_FAILED", error)
        }
    }

    private fun resolveTheme(preferredTheme: String?): VKIDAuthParams.Theme {
        return when (preferredTheme) {
            "dark" -> VKIDAuthParams.Theme.Dark
            "light" -> VKIDAuthParams.Theme.Light
            else -> if (isNightModeEnabled()) VKIDAuthParams.Theme.Dark else VKIDAuthParams.Theme.Light
        }
    }

    private fun isNightModeEnabled(): Boolean {
        val uiModeMask = activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return uiModeMask == Configuration.UI_MODE_NIGHT_YES
    }

    private fun ensureVkIdInitialized() {
        if (vkIdInitialized) return

        synchronized(this) {
            if (vkIdInitialized) return
            VKID.init(activity.applicationContext)
            vkIdInitialized = true
        }
    }
}
