package app.tauri.socialauth

import android.app.Activity
import android.content.res.Configuration
import android.os.CancellationSignal
import androidx.activity.result.ActivityResult
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.lifecycle.LifecycleOwner
import app.tauri.Logger
import app.tauri.annotation.ActivityCallback
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import com.vk.id.AccessToken
import com.vk.id.VKID
import com.vk.id.VKIDAuthFail
import com.vk.id.auth.VKIDAuthCallback
import com.vk.id.auth.VKIDAuthParams
import com.yandex.authsdk.YandexAuthLoginOptions
import com.yandex.authsdk.YandexAuthOptions
import com.yandex.authsdk.YandexAuthResult
import com.yandex.authsdk.YandexAuthSdk

@InvokeArg
class VkSignInArgs {
    var theme: String? = null
}

@TauriPlugin
class SocialAuthPlugin(private val activity: Activity) : Plugin(activity) {
    companion object {
        @Volatile
        private var vkIdInitialized = false
    }

    private var lastGoogleWebClientId: String? = null
    private val credentialManager: CredentialManager by lazy { CredentialManager.create(activity) }
    private val yandexAuthSdk: YandexAuthSdk by lazy {
        YandexAuthSdk.create(YandexAuthOptions(activity.applicationContext))
    }

    @Command
    fun googleSignIn(invoke: Invoke) {
        try {
            val webClientId = resolveGoogleServerClientId()
            if (webClientId.isNullOrBlank()) {
                invoke.reject("Google Sign-In failed: GOOGLE_SERVER_CLIENT_ID is empty", "GOOGLE_SIGN_IN_INIT_FAILED")
                return
            }

            lastGoogleWebClientId = webClientId
            val googleIdOption =
                GetGoogleIdOption.Builder()
                    .setServerClientId(webClientId)
                    .setFilterByAuthorizedAccounts(false)
                    .setAutoSelectEnabled(false)
                    .build()
            val request =
                GetCredentialRequest.Builder()
                    .addCredentialOption(googleIdOption)
                    .build()

            credentialManager.getCredentialAsync(
                activity,
                request,
                CancellationSignal(),
                activity.mainExecutor,
                object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                    override fun onResult(result: GetCredentialResponse) {
                        resolveWithGoogleToken(invoke, result)
                    }

                    override fun onError(error: GetCredentialException) {
                        rejectWithGoogleCredentialError(invoke, error)
                    }
                },
            )
        } catch (error: Exception) {
            invoke.reject("Google Sign-In initialization failed", "GOOGLE_SIGN_IN_INIT_FAILED", error)
        }
    }

    @Command
    fun vkSignIn(invoke: Invoke) {
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
            authParamsBuilder.theme = resolveVkTheme(preferredTheme)
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

    @Command
    fun yandexSignIn(invoke: Invoke) {
        try {
            val intent = yandexAuthSdk.contract.createIntent(activity, YandexAuthLoginOptions())
            startActivityForResult(invoke, intent, "onYandexSignInResult")
        } catch (error: Exception) {
            invoke.reject("Yandex Sign-In initialization failed", "YANDEX_AUTH_INIT_FAILED", error)
        }
    }

    @Command
    fun appleSignIn(invoke: Invoke) {
        invoke.reject(
            "Apple Sign-In is not supported on Android",
            "SOCIAL_AUTH_UNSUPPORTED_PLATFORM",
        )
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

    private fun resolveGoogleServerClientId(): String? {
        val packageName = activity.applicationContext.packageName
        return runCatching {
            val buildConfigClass = Class.forName("$packageName.BuildConfig")
            val raw = buildConfigClass.getField("GOOGLE_SERVER_CLIENT_ID").get(null) as? String
            raw?.trim()
        }.getOrNull()
    }

    private fun resolveWithGoogleToken(invoke: Invoke, result: GetCredentialResponse) {
        try {
            val credential = result.credential
            if (credential !is CustomCredential ||
                credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                invoke.reject(
                    "Google Sign-In failed: unsupported credential type ${credential.type}",
                    "GOOGLE_UNSUPPORTED_CREDENTIAL",
                )
                return
            }

            val googleIdTokenCredential = GoogleIdTokenCredential.createFrom(credential.data)
            val idToken = googleIdTokenCredential.idToken

            if (idToken.isNullOrBlank()) {
                invoke.reject("Google Sign-In failed: idToken is empty", "GOOGLE_ID_TOKEN_EMPTY")
                return
            }

            val data = JSObject()
            data.put("idToken", idToken)
            invoke.resolve(data)
        } catch (error: GoogleIdTokenParsingException) {
            invoke.reject("Google Sign-In failed: invalid Google token payload", "GOOGLE_TOKEN_PARSE_FAILED", error)
        } catch (error: Exception) {
            invoke.reject("Google Sign-In failed", "GOOGLE_SIGN_IN_FAILED", error)
        }
    }

    private fun rejectWithGoogleCredentialError(invoke: Invoke, error: GetCredentialException) {
        if (error is GetCredentialCancellationException) {
            invoke.reject("Google Sign-In canceled by user", "GOOGLE_AUTH_CANCELED")
            return
        }

        val details =
            "type=${error.type}, package=${activity.packageName}, webClientId=${lastGoogleWebClientId ?: "unknown"}"
        Logger.error(Logger.tags("GoogleAuth"), "Credential Manager Google sign-in failed: $details", error)
        invoke.reject(
            "Google Sign-In failed via Credential Manager ($details)",
            "GOOGLE_CREDENTIAL_MANAGER_FAILED",
            error,
        )
    }

    private fun resolveVkTheme(preferredTheme: String?): VKIDAuthParams.Theme {
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
