package com.shieldinfo.simbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
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
 * 3. Ensures SmsReceiver keeps working even when screen is off
 */
class WatchdogService : Service() {

    companion object {
        private const val TAG = "SimBox.Watchdog"
        private const val CHANNEL_ID = "simbox_watchdog"
        private const val NOTIF_ID = 1001
        private const val HEARTBEAT_INTERVAL_MS = 5 * 60 * 1000L // 5 minutes
    }

    private val handler = Handler(Looper.getMainLooper())
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
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY // restart automatically if killed
    }

    override fun onDestroy() {
        handler.removeCallbacks(heartbeatRunnable)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun sendHeartbeat() {
        Config.load(this)
        if (!Config.isConfigured()) return
        Thread {
            // 1. Send heartbeat ping
            ApiClient.heartbeat(Config.backendUrl, Config.simSecret, Config.simNumber)
            Log.d(TAG, "💓 Heartbeat sent")

            // 2. Retry any failed SMS forwards from the queue
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
