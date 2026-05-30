package com.shieldinfo.simbox

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Simple retry queue using SharedPreferences.
 *
 * When SMS forward fails (network down, backend restart, etc.),
 * we store it here and retry on the next heartbeat (every 5 min).
 *
 * Keeps max 50 pending SMS to avoid unbounded growth.
 */
object RetryQueue {

    private const val TAG = "SimBox.RetryQueue"
    private const val PREFS_NAME = "retry_queue"
    private const val KEY_QUEUE = "pending"
    private const val MAX_ITEMS = 50
    private const val MAX_RETRIES = 5

    data class PendingSms(
        val from: String,
        val body: String,
        val timestamp: Long,
        val retries: Int = 0
    )

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun add(ctx: Context, from: String, body: String) {
        val list = getAll(ctx).toMutableList()
        if (list.size >= MAX_ITEMS) list.removeAt(0) // drop oldest
        list.add(PendingSms(from, body, System.currentTimeMillis()))
        save(ctx, list)
        Log.d(TAG, "Added to retry queue: from=$from (queue size: ${list.size})")
    }

    fun retryAll(ctx: Context) {
        val pending = getAll(ctx)
        if (pending.isEmpty()) return

        Log.d(TAG, "Retrying ${pending.size} pending SMS")
        Config.load(ctx)
        if (!Config.isConfigured()) return

        val stillPending = mutableListOf<PendingSms>()

        for (sms in pending) {
            if (sms.retries >= MAX_RETRIES) {
                Log.w(TAG, "Dropping SMS after $MAX_RETRIES retries: ${sms.from}")
                continue
            }
            val success = ApiClient.forwardSms(
                Config.backendUrl, Config.simSecret, Config.simNumber,
                sms.from, sms.body
            )
            if (success) {
                Log.i(TAG, "✅ Retry succeeded for SMS from ${sms.from}")
            } else {
                stillPending.add(sms.copy(retries = sms.retries + 1))
            }
        }

        save(ctx, stillPending)
        if (stillPending.isNotEmpty()) {
            Log.w(TAG, "${stillPending.size} SMS still pending after retry")
        }
    }

    fun size(ctx: Context): Int = getAll(ctx).size

    private fun getAll(ctx: Context): List<PendingSms> {
        val json = prefs(ctx).getString(KEY_QUEUE, "[]") ?: "[]"
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map {
                val obj = arr.getJSONObject(it)
                PendingSms(
                    from      = obj.getString("from"),
                    body      = obj.getString("body"),
                    timestamp = obj.getLong("timestamp"),
                    retries   = obj.optInt("retries", 0)
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun save(ctx: Context, list: List<PendingSms>) {
        val arr = JSONArray()
        list.forEach { sms ->
            arr.put(JSONObject().apply {
                put("from", sms.from)
                put("body", sms.body)
                put("timestamp", sms.timestamp)
                put("retries", sms.retries)
            })
        }
        prefs(ctx).edit().putString(KEY_QUEUE, arr.toString()).apply()
    }
}
