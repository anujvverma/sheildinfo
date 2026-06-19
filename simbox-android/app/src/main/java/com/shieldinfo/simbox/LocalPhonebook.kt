package com.shieldinfo.simbox

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Local phonebook cache stored in SharedPreferences.
 *
 * Instead of making a network call on every incoming call (too slow — call
 * would ring 3-4 times before we get an answer), we keep a local copy of
 * the allowed numbers and sync it from the backend every 5 minutes.
 *
 * Call blocking decision is instant — no network needed.
 */
object LocalPhonebook {

    private const val TAG = "SimBox.Phonebook"
    private const val PREFS_NAME = "local_phonebook"
    private const val KEY_CONTACTS = "contacts"
    private const val KEY_DELIVERY_MODE_UNTIL = "delivery_mode_until"
    private const val KEY_LAST_SYNC = "last_sync"

    data class Contact(val number: String, val name: String)

    // ─── READ ──────────────────────────────────────────────────

    fun isAllowed(ctx: Context, callerNumber: String): Boolean {
        val normalised = normalise(callerNumber)

        // Delivery mode — allow everyone
        val deliveryUntil = getDeliveryModeUntil(ctx)
        if (deliveryUntil > System.currentTimeMillis()) {
            Log.i(TAG, "📦 Delivery mode active — allowing $normalised")
            return true
        }

        val contacts = getAll(ctx)
        val allowed = contacts.any { normalise(it.number) == normalised }
        Log.i(TAG, if (allowed) "✅ $normalised in phonebook" else "🚫 $normalised NOT in phonebook")
        return allowed
    }

    fun getAll(ctx: Context): List<Contact> {
        val json = prefs(ctx).getString(KEY_CONTACTS, "[]") ?: "[]"
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map {
                val obj = arr.getJSONObject(it)
                Contact(obj.getString("number"), obj.optString("name", ""))
            }
        } catch (e: Exception) { emptyList() }
    }

    fun getDeliveryModeUntil(ctx: Context): Long =
        prefs(ctx).getLong(KEY_DELIVERY_MODE_UNTIL, 0L)

    fun getLastSync(ctx: Context): Long =
        prefs(ctx).getLong(KEY_LAST_SYNC, 0L)

    // ─── WRITE (called by sync) ────────────────────────────────

    fun update(ctx: Context, contacts: List<Contact>, deliveryModeUntilMs: Long = 0L) {
        val arr = JSONArray()
        contacts.forEach { c ->
            arr.put(JSONObject().apply {
                put("number", c.number)
                put("name", c.name)
            })
        }
        prefs(ctx).edit()
            .putString(KEY_CONTACTS, arr.toString())
            .putLong(KEY_DELIVERY_MODE_UNTIL, deliveryModeUntilMs)
            .putLong(KEY_LAST_SYNC, System.currentTimeMillis())
            .apply()
        Log.i(TAG, "📋 Phonebook updated: ${contacts.size} contacts, delivery=${deliveryModeUntilMs > System.currentTimeMillis()}")
    }

    // ─── HELPERS ──────────────────────────────────────────────

    fun normalise(number: String): String {
        var n = number.replace(Regex("[\\s\\-()]"), "")
        if (n.startsWith("0")) n = "+91" + n.substring(1)
        if (n.startsWith("91") && n.length == 12) n = "+$n"
        if (!n.startsWith("+")) n = "+91$n"
        return n
    }

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
