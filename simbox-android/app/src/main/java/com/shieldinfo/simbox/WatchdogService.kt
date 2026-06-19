package com.shieldinfo.simbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the app alive.
 *
 * Android aggressively kills background apps. This service:
 * 1. Shows a persistent notification ("ShieldInfo SIM Box is active")
 * 2. Sends a heartbeat to your backend every 5 minutes
 * 3. Watches SMS inbox via ContentObserver (reliable on Vivo/Chinese ROMs)
 * 4. Ensures SmsReceiver keeps working even when screen is off
 */
class WatchdogService : Service() {

    companion object {
        private const val TAG = "SimBox.Watchdog"
        private const val CHANNEL_ID = "simbox_watchdog"
        private const val NOTIF_ID = 1001
        private const val HEARTBEAT_INTERVAL_MS = 5 * 60 * 1000L // 5 minutes
        private const val PREF_LAST_SMS_ID = "last_processed_sms_id"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var smsObserver: ContentObserver? = null

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            sendHeartbeat()
            handler.postDelayed(this, HEARTBEAT_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("SIM Box active — forwarding SMS"))
        Log.i(TAG, "WatchdogService started")
        handler.post(heartbeatRunnable)
        registerSmsObserver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY // restart automatically if killed
    }

    override fun onDestroy() {
        handler.removeCallbacks(heartbeatRunnable)
        smsObserver?.let { contentResolver.unregisterContentObserver(it) }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── ContentObserver: watches SMS inbox directly, bypasses broadcast priority issues ──

    private fun registerSmsObserver() {
        val smsUri = Uri.parse("content://sms/inbox")
        smsObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                checkForNewSms()
            }
        }
        contentResolver.registerContentObserver(smsUri, true, smsObserver!!)
        // Also initialise the last-seen ID so we don't re-forward old messages on restart
        initLastSmsId()
        Log.i(TAG, "📡 SMS ContentObserver registered")
    }

    private fun initLastSmsId() {
        val prefs = getSharedPreferences("simbox_watchdog", MODE_PRIVATE)
        if (prefs.getLong(PREF_LAST_SMS_ID, -1L) == -1L) {
            // Store the current newest SMS id so we don't forward history
            val cursor = contentResolver.query(
                Uri.parse("content://sms/inbox"),
                arrayOf("_id"), null, null, "_id DESC LIMIT 1"
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    val id = it.getLong(0)
                    prefs.edit().putLong(PREF_LAST_SMS_ID, id).apply()
                    Log.d(TAG, "Initialised last SMS id: $id")
                }
            }
        }
    }

    private fun checkForNewSms() {
        Config.load(this)
        if (!Config.isConfigured()) return

        val prefs = getSharedPreferences("simbox_watchdog", MODE_PRIVATE)
        val lastId = prefs.getLong(PREF_LAST_SMS_ID, 0L)

        val cursor = contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("_id", "address", "body", "date"),
            "_id > ?", arrayOf(lastId.toString()),
            "_id ASC"
        ) ?: return

        cursor.use {
            while (it.moveToNext()) {
                val id   = it.getLong(it.getColumnIndexOrThrow("_id"))
                val from = it.getString(it.getColumnIndexOrThrow("address")) ?: "unknown"
                val body = it.getString(it.getColumnIndexOrThrow("body")) ?: ""

                Log.i(TAG, "📱 ContentObserver caught SMS from $from: ${body.take(30)}")

                Thread {
                    val ok = ApiClient.forwardSms(
                        Config.backendUrl, Config.simSecret, Config.simNumber, from, body
                    )
                    if (!ok) RetryQueue.add(this@WatchdogService, from, body)
                    else Log.i(TAG, "✅ ContentObserver forwarded SMS id=$id")
                }.start()

                // Always advance the pointer even if forward fails (RetryQueue handles retry)
                prefs.edit().putLong(PREF_LAST_SMS_ID, id).apply()
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────

    private fun sendHeartbeat() {
        Config.load(this)
        if (!Config.isConfigured()) return
        Thread {
            // 1. Send heartbeat ping
            ApiClient.heartbeat(Config.backendUrl, Config.simSecret, Config.simNumber)
            Log.d(TAG, "💓 Heartbeat sent")

            // 2. Sync phonebook from backend (so call blocking is up to date)
            PhonebookSync.sync(this@WatchdogService)

            // 3. Retry any failed SMS forwards from the queue
            val pending = RetryQueue.size(this@WatchdogService)
            if (pending > 0) {
                Log.i(TAG, "🔄 Retrying $pending queued SMS...")
                RetryQueue.retryAll(this@WatchdogService)
            }
        }.start()
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ShieldInfo SIM Box")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)  // can't be swiped away
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SIM Box Status",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps ShieldInfo SIM Box running in the background"
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
