package com.shieldinfo.simbox

import android.content.Context
import android.content.SharedPreferences

/**
 * Stores configuration in SharedPreferences.
 * User sets these once in the MainActivity setup screen.
 */
object Config {

    private const val PREFS_NAME = "simbox_config"

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // Your Railway backend URL e.g. https://shieldnumber-backend.up.railway.app
    var backendUrl: String
        get() = _backendUrl
        set(value) { _backendUrl = value }

    var simSecret: String
        get() = _simSecret
        set(value) { _simSecret = value }

    // The Jio SIM number in this phone e.g. +919876543210
    var simNumber: String
        get() = _simNumber
        set(value) { _simNumber = value }

    private var _backendUrl = ""
    private var _simSecret = ""
    private var _simNumber = ""

    fun load(ctx: Context) {
        val p = prefs(ctx)
        _backendUrl = p.getString("backend_url", "") ?: ""
        _simSecret  = p.getString("sim_secret", "shieldinfo-sim-secret-2026") ?: "shieldinfo-sim-secret-2026"
        _simNumber  = p.getString("sim_number", "") ?: ""
    }

    fun save(ctx: Context, backendUrl: String, simSecret: String, simNumber: String) {
        _backendUrl = backendUrl
        _simSecret  = simSecret
        _simNumber  = simNumber
        prefs(ctx).edit()
            .putString("backend_url", backendUrl)
            .putString("sim_secret", simSecret)
            .putString("sim_number", simNumber)
            .apply()
    }

    fun isConfigured(): Boolean =
        _backendUrl.isNotBlank() && _simNumber.isNotBlank()
}
