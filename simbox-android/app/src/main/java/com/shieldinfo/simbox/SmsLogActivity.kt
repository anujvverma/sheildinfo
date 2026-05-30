package com.shieldinfo.simbox

import android.content.SharedPreferences
import android.os.Bundle
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.*

/**
 * Shows a local log of all SMS received and forwarded.
 * Accessible from MainActivity via "View Log" button.
 */
class SmsLogActivity : AppCompatActivity() {

    companion object {
        private const val PREFS_NAME = "sms_log"
        private const val KEY_LOG = "entries"
        private const val MAX_LOG = 100

        fun appendLog(prefs: SharedPreferences, from: String, body: String, forwarded: Boolean) {
            val arr = try { JSONArray(prefs.getString(KEY_LOG, "[]")) } catch (e: Exception) { JSONArray() }
            val entry = org.json.JSONObject().apply {
                put("from", from)
                put("body", body.take(120))
                put("forwarded", forwarded)
                put("time", System.currentTimeMillis())
            }
            // Prepend newest entry
            val newArr = JSONArray()
            newArr.put(entry)
            for (i in 0 until minOf(arr.length(), MAX_LOG - 1)) newArr.put(arr.get(i))
            prefs.edit().putString(KEY_LOG, newArr.toString()).apply()
        }
    }

    private val sdf = SimpleDateFormat("dd MMM HH:mm", Locale.getDefault())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val raw = prefs.getString(KEY_LOG, "[]") ?: "[]"
        val arr = try { JSONArray(raw) } catch (e: Exception) { JSONArray() }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
        }

        val title = TextView(this).apply {
            text = "📩 Forwarded SMS Log"
            textSize = 20f
            setTypeface(null, android.graphics.Typeface.BOLD)
            setPadding(0, 0, 0, 16)
        }
        layout.addView(title)

        if (arr.length() == 0) {
            layout.addView(TextView(this).apply {
                text = "No SMS forwarded yet.\nWaiting for messages..."
                textSize = 14f
                setTextColor(0xFF94A3B8.toInt())
            })
        } else {
            for (i in 0 until arr.length()) {
                val entry = arr.getJSONObject(i)
                val card = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(16, 16, 16, 16)
                    setBackgroundColor(0xFFFFFFFF.toInt())
                    val params = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    )
                    params.setMargins(0, 0, 0, 12)
                    layoutParams = params
                }

                val forwarded = entry.optBoolean("forwarded", true)
                val timeMs = entry.optLong("time", 0)
                val timeStr = if (timeMs > 0) sdf.format(Date(timeMs)) else ""

                card.addView(TextView(this).apply {
                    text = "${if (forwarded) "✅" else "❌"} From: ${entry.getString("from")}   $timeStr"
                    textSize = 12f
                    setTextColor(if (forwarded) 0xFF166534.toInt() else 0xFF991B1B.toInt())
                })
                card.addView(TextView(this).apply {
                    text = entry.getString("body")
                    textSize = 13f
                    setPadding(0, 6, 0, 0)
                    setTextColor(0xFF1A1A2E.toInt())
                })

                layout.addView(card)
            }
        }

        val scroll = ScrollView(this)
        scroll.addView(layout)
        setContentView(scroll)
        title(this, "SMS Log")
    }

    private fun title(activity: AppCompatActivity, t: String) {
        activity.supportActionBar?.title = t
    }
}
