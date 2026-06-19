package com.shieldinfo.simbox

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Syncs the phonebook from ShieldInfo backend into local cache.
 * Called every 5 minutes by WatchdogService.
 *
 * Backend endpoint: GET /webhook/simbox-phonebook?simNumber=+91XXXXXXXXXX
 * Returns: { contacts: [{number, name}], deliveryModeUntil: timestamp_ms }
 */
object PhonebookSync {

    private const val TAG = "SimBox.PhonebookSync"

    fun sync(ctx: Context) {
        Config.load(ctx)
        if (!Config.isConfigured()) return

        try {
            val url = "${Config.backendUrl}/webhook/simbox-phonebook" +
                      "?simNumber=${java.net.URLEncoder.encode(Config.simNumber, "UTF-8")}"

            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 10_000
                readTimeout = 10_000
                setRequestProperty("X-Sim-Secret", Config.simSecret)
            }

            if (conn.responseCode != 200) {
                Log.w(TAG, "Sync failed: HTTP ${conn.responseCode}")
                conn.disconnect()
                return
            }

            val body = BufferedReader(InputStreamReader(conn.inputStream)).readText()
            conn.disconnect()

            val json = JSONObject(body)
            val arr = json.getJSONArray("contacts")
            val contacts = (0 until arr.length()).map {
                val obj = arr.getJSONObject(it)
                LocalPhonebook.Contact(
                    number = obj.getString("number"),
                    name   = obj.optString("name", "")
                )
            }

            val deliveryUntil = json.optLong("deliveryModeUntil", 0L)
            LocalPhonebook.update(ctx, contacts, deliveryUntil)
            Log.i(TAG, "✅ Synced ${contacts.size} contacts from backend")

        } catch (e: Exception) {
            Log.e(TAG, "Sync exception: ${e.message}")
        }
    }
}
