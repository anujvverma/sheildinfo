package com.shieldinfo.simbox

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat

/**
 * CALL BLOCKING ENGINE — Android 10+ (API 29+)
 *
 * This service is called by Android for every incoming call BEFORE the phone rings.
 * We check the local phonebook and either:
 *   - Allow: let the call ring through (will forward via call forwarding settings)
 *   - Block: reject silently + notify the user via local notification
 *
 * User must set ShieldInfo as their "Caller ID & Spam" app in Phone settings.
 * We prompt them to do this in MainActivity.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class ShieldCallScreeningService : CallScreeningService() {

    companion object {
        private const val TAG = "SimBox.CallScreening"
        private const val CHANNEL_ID = "blocked_calls"
        private var notifId = 2000
    }

    override fun onScreenCall(callDetails: Call.Details) {
        val rawNumber = callDetails.handle?.schemeSpecificPart ?: ""
        val callerNumber = LocalPhonebook.normalise(rawNumber)

        Log.i(TAG, "📞 Incoming call from: $callerNumber")

        val allowed = LocalPhonebook.isAllowed(applicationContext, callerNumber)

        val response = CallResponse.Builder()

        if (allowed) {
            Log.i(TAG, "✅ ALLOWED — $callerNumber is in phonebook")
            // Let it ring — call forwarding will connect to real user's phone
            response.setRejectCall(false)
                    .setDisallowCall(false)
                    .setSkipCallLog(false)

            // Notify backend (fire and forget)
            Thread {
                logCallToBackend(callerNumber, "allowed", "phonebook")
            }.start()

        } else {
            Log.i(TAG, "🚫 BLOCKED — $callerNumber is unknown")
            // Reject silently — caller hears busy tone, phone never rings
            response.setRejectCall(true)
                    .setDisallowCall(true)
                    .setSkipCallLog(false)
                    .setSilenceCall(true)

            // Show local notification so user knows someone tried to call
            showBlockedNotification(callerNumber)

            // Notify backend (fire and forget)
            Thread {
                logCallToBackend(callerNumber, "blocked", "unknown")
                notifyUserPush(callerNumber)
            }.start()
        }

        respondToCall(callDetails, response.build())
    }

    private fun showBlockedNotification(callerNumber: String) {
        createNotifChannel()
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("🛡️ Call Blocked")
            .setContentText("Unknown caller $callerNumber was blocked")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        getSystemService(NotificationManager::class.java)
            .notify(notifId++, notif)
    }

    private fun logCallToBackend(callerNumber: String, action: String, reason: String) {
        Config.load(applicationContext)
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
            Log.w(TAG, "Failed to log call: ${e.message}")
        }
    }

    private fun notifyUserPush(callerNumber: String) {
        // Backend will push-notify the real user via FCM
        // The logCallToBackend already tells backend — backend handles FCM
    }

    private fun createNotifChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID, "Blocked Calls", NotificationManager.IMPORTANCE_HIGH
        ).apply { description = "Notifications for blocked calls" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
