package com.shieldinfo.simbox

import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Simple HTTP client — no external libraries needed for POC.
 * Runs on a background thread (never call from main thread).
 */
object ApiClient {

    private const val TAG = "SimBox.ApiClient"
    private const val TIMEOUT_MS = 15_000

    /**
     * Forward an incoming SMS to the ShieldInfo backend.
     * Backend will push-notify the real user.
     */
    fun forwardSms(
        backendUrl: String,
        simSecret: String,
        simNumber: String,
        from: String,
        body: String
    ): Boolean {
        return try {
            val endpoint = "$backendUrl/webhook/sms-inbound"
            val payload = JSONObject().apply {
                put("from", from)
                put("body", body)
                put("simNumber", simNumber)
                put("timestamp", System.currentTimeMillis())
            }.toString()

            Log.d(TAG, "Forwarding SMS from $from → $endpoint")

            val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("X-Sim-Secret", simSecret)
                setRequestProperty("X-Sim-Number", simNumber)
            }

            OutputStreamWriter(conn.outputStream).use { it.write(payload) }

            val code = conn.responseCode
            Log.d(TAG, "Response: $code")
            conn.disconnect()

            code in 200..299
        } catch (e: Exception) {
            Log.e(TAG, "Failed to forward SMS", e)
            false
        }
    }

    /**
     * Heartbeat ping — called every 5 minutes by WatchdogService.
     * Lets your backend know this SIM box is alive.
     */
    fun heartbeat(backendUrl: String, simSecret: String, simNumber: String) {
        try {
            val endpoint = "$backendUrl/webhook/simbox-heartbeat"
            val payload = JSONObject().apply {
                put("simNumber", simNumber)
                put("timestamp", System.currentTimeMillis())
            }.toString()

            val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8_000
                readTimeout = 8_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("X-Sim-Secret", simSecret)
            }
            OutputStreamWriter(conn.outputStream).use { it.write(payload) }
            conn.responseCode
            conn.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "Heartbeat failed: ${e.message}")
        }
    }
}
