package com.shieldinfo.simbox

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Auto-starts WatchdogService when the Android phone reboots.
 * This means even if someone unplugs/replug the phone,
 * the SIM box comes back online automatically without any manual action.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i("SimBox.Boot", "Device booted — starting WatchdogService")
            val serviceIntent = Intent(context, WatchdogService::class.java)
            context.startForegroundService(serviceIntent)
        }
    }
}
