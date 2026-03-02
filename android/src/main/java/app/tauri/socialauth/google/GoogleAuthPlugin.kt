package app.tauri.socialauth.google

import android.app.Activity
import android.os.CancellationSignal
import app.tauri.Logger
import app.tauri.annotation.Command
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException

@TauriPlugin
class GoogleAuthPlugin(private val activity: Activity) : Plugin(activity) {
    private var lastWebClientId: String? = null
    private val credentialManager: CredentialManager by lazy { CredentialManager.create(activity) }

    @Command
    fun signIn(invoke: Invoke) {
        try {
            val webClientId = resolveGoogleServerClientId()
            if (webClientId.isNullOrBlank()) {
                invoke.reject("Google Sign-In failed: GOOGLE_SERVER_CLIENT_ID is empty", "GOOGLE_SIGN_IN_INIT_FAILED")
                return
            }

            lastWebClientId = webClientId
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
                        rejectWithCredentialError(invoke, error)
                    }
                },
            )
        } catch (error: Exception) {
            invoke.reject("Google Sign-In initialization failed", "GOOGLE_SIGN_IN_INIT_FAILED", error)
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

    private fun rejectWithCredentialError(invoke: Invoke, error: GetCredentialException) {
        if (error is GetCredentialCancellationException) {
            invoke.reject("Google Sign-In canceled by user", "GOOGLE_AUTH_CANCELED")
            return
        }

        val details =
            "type=${error.type}, package=${activity.packageName}, webClientId=${lastWebClientId ?: "unknown"}"
        Logger.error(Logger.tags("GoogleAuth"), "Credential Manager Google sign-in failed: $details", error)
        invoke.reject(
            "Google Sign-In failed via Credential Manager ($details)",
            "GOOGLE_CREDENTIAL_MANAGER_FAILED",
            error,
        )
    }
}
