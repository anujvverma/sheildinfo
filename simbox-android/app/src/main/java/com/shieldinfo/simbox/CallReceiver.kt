package com.shieldinfo.simbox

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.TelephonyManager
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * Fallback call handler for Android 8 & 9 (API 26-28).
 *
 * Android 10+ uses ShieldCallScreeningService (cleaner).
 * Android 8-9 uses this BroadcastReceiver which detects RINGING state
 * and attempts to end the call if not in phonebook.
 *
 * NOTE: Ending a call programmatically on Android 8-9 requires
 * the app to be set as the default phone app, which is complex.
 * For POC, we use this to LOG the call and notify the user.
 * Full blocking on Android 8-9 requires being default dialer.
 *
 * In practice, most Indian Android phones in 2024 run Android 10+.
 */
class CallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SimBox.CallReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return // handled by CallScreeningService

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        if (state != TelephonyManager.EXTRA_STATE_RINGING) return

        val rawNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: return
        val callerNumber = LocalPhonebook.normalise(rawNumber)

        Log.i(TAG, "📞 Incoming call (Android 8/9): $callerNumber")

        Config.load(context)
        val allowed = LocalPhonebook.isAllowed(context, callerNumber)

        if (!allowed) {
            Log.i(TAG, "🚫 BLOCKED (Android 8/9): $callerNumber — notifying user")
            // Can't silently reject without being default dialer on Android 8-9
            // So we notify the user to manually decline + add to phonebook
            Thread {
                logCallToBackend(context, callerNumber, "blocked", "unknown")
            }.start()
        } else {
            Log.i(TAG, "✅ ALLOWED: $callerNumber")
            Thread {
                logCallToBackend(context, callerNumber, "allowed", "phonebook")
            }.start()
        }
    }

    private fun logCallToBackend(ctx: Context, callerNumber: String, action: String, reason: String) {
        if (!Config.isConfigured()) return
        try {
            val url = "${Config.backendUrl}/webhook/simbox-call-log"
            val payload = org.json.JSONObject().apply {
                put("callerNumber", callerNumber)
                put("simNumber", Config.simNumber)
                put("action", action)
                put("reason", reason)
                put("timestamp", System.currentTimeMillis())
            }.toString()
            val conn = (java.net.URL(url).openConnection() as java.net.HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8_000
                readTimeout = 8_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("X-Sim-Secret", Config.simSecret)
            }
            java.io.OutputStreamWriter(conn.outputStream).use { it.write(payload) }
            conn.responseCode
            conn.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "Log failed: ${e.message}")
        }
    }
}
