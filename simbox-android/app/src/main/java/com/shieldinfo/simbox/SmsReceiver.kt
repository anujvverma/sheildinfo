package com.shieldinfo.simbox

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * THE CORE of ShieldInfo SIM Box.
 *
 * Fires instantly when an SMS arrives on the Jio SIM — even with screen off.
 * Forwards to ShieldInfo backend → backend push-notifies the real user.
 * On failure → queued for automatic retry every 5 minutes.
 */
class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SimBox.SmsReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        Config.load(context)
        if (!Config.isConfigured()) {
            Log.w(TAG, "Not configured — ignoring SMS")
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        val from = messages[0].originatingAddress ?: "unknown"
        val body = messages.joinToString("") { it.messageBody }

        Log.i(TAG, "📩 SMS from: $from | ${body.take(60)}...")

        val pendingResult = goAsync()

        Thread {
            try {
                val success = ApiClient.forwardSms(
                    backendUrl = Config.backendUrl,
                    simSecret  = Config.simSecret,
                    simNumber  = Config.simNumber,
                    from       = from,
                    body       = body
                )
                if (success) {
                    Log.i(TAG, "✅ Forwarded immediately")
                } else {
                    Log.w(TAG, "⚠️  Forward failed — queuing for retry")
                    RetryQueue.add(context, from, body)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception forwarding SMS", e)
                RetryQueue.add(context, from, body)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }
}
