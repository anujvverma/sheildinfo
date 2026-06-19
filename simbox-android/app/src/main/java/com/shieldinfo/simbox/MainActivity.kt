package com.shieldinfo.simbox

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.telephony.TelephonyManager
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * One-time setup screen.
 * Anuj opens this app on the old Android phone, enters:
 *   1. Backend URL  (e.g. https://shieldnumber.up.railway.app)
 *   2. SIM Secret   (shared secret so backend trusts this device)
 *   3. SIM Number   (the Jio number — auto-detected if possible)
 *
 * After saving, the WatchdogService starts and this screen can be ignored forever.
 */
class MainActivity : AppCompatActivity() {

    companion object {
        private const val PERMISSION_REQUEST_CODE = 101
        private val REQUIRED_PERMISSIONS = arrayOf(
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
            Manifest.permission.READ_PHONE_STATE
        )
    }

    private lateinit var etBackendUrl: EditText
    private lateinit var etSimSecret: EditText
    private lateinit var etSimNumber: EditText
    private lateinit var tvStatus: TextView
    private lateinit var btnSave: Button
    private lateinit var btnTestSms: Button
    private lateinit var btnViewLog: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        etBackendUrl = findViewById(R.id.etBackendUrl)
        etSimSecret  = findViewById(R.id.etSimSecret)
        etSimNumber  = findViewById(R.id.etSimNumber)
        tvStatus     = findViewById(R.id.tvStatus)
        btnSave      = findViewById(R.id.btnSave)
        btnTestSms   = findViewById(R.id.btnTestSms)
        btnViewLog   = findViewById(R.id.btnViewLog)

        Config.load(this)

        // Pre-fill saved values
        if (Config.isConfigured()) {
            etBackendUrl.setText(Config.backendUrl)
            etSimSecret.setText(Config.simSecret)
            etSimNumber.setText(Config.simNumber)
            setStatus("✅ Configured — SIM Box is active", green = true)
        } else {
            etBackendUrl.setText("https://sheildinfo-production.up.railway.app")
            etSimSecret.setText("shieldinfo-sim-secret-2026")
            etSimNumber.setText("+916356564558")
            tryAutoDetectSimNumber() // overrides with real SIM number if detectable
        }

        btnSave.setOnClickListener { saveAndStart() }
        btnTestSms.setOnClickListener { sendTestSms() }
        btnViewLog.setOnClickListener {
            startActivity(Intent(this, SmsLogActivity::class.java))
        }

        // Show call screening setup status
        checkCallScreeningStatus()

        checkAndRequestPermissions()
    }

    private fun saveAndStart() {
        val url    = etBackendUrl.text.toString().trim().trimEnd('/')
        val secret = etSimSecret.text.toString().trim()
        val simNum = etSimNumber.text.toString().trim()

        if (url.isEmpty() || simNum.isEmpty()) {
            setStatus("❌ Backend URL and SIM Number are required", green = false)
            return
        }

        Config.save(this, url, secret, simNum)
        setStatus("✅ Saved! SIM Box is now active.", green = true)

        // Start the watchdog foreground service
        val intent = Intent(this, WatchdogService::class.java)
        startForegroundService(intent)

        Toast.makeText(this, "SIM Box started! You can minimize this app.", Toast.LENGTH_LONG).show()
    }

    private fun sendTestSms() {
        Config.load(this)
        if (!Config.isConfigured()) {
            setStatus("❌ Save config first", green = false)
            return
        }
        setStatus("⏳ Sending test ping to backend...", green = true)
        Thread {
            val success = ApiClient.forwardSms(
                backendUrl = Config.backendUrl,
                simSecret  = Config.simSecret,
                simNumber  = Config.simNumber,
                from       = "TEST_DEVICE",
                body       = "ShieldInfo SIM Box test message — if you see this, SMS forwarding is working! ✅"
            )
            runOnUiThread {
                if (success) {
                    setStatus("✅ Test message sent! Check your ShieldInfo app.", green = true)
                } else {
                    setStatus("❌ Test failed — check your backend URL and make sure it's running", green = false)
                }
            }
        }.start()
    }

    private fun checkCallScreeningStatus() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.Q) return
        val telecom = getSystemService(android.telecom.TelecomManager::class.java)
        val pkg = telecom?.defaultDialerPackage ?: ""
        // Check if we are set as call screening app
        // We show a prompt to guide user if not yet set
        val infoText = findViewById<TextView>(R.id.tvCallScreeningInfo)
        if (pkg == packageName) {
            infoText?.text = "✅ Call screening active — unknown callers will be blocked"
            infoText?.setTextColor(getColor(android.R.color.holo_green_dark))
        } else {
            infoText?.text = "⚠️ Tap here to enable Call Blocking"
            infoText?.setTextColor(getColor(android.R.color.holo_orange_dark))
            infoText?.setOnClickListener { openCallScreeningSettings() }
        }
    }

    private fun openCallScreeningSettings() {
        // Guide user to Phone app settings to set ShieldInfo as screening app
        try {
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = android.net.Uri.parse("package:$packageName")
            }
            startActivity(intent)
            Toast.makeText(this,
                "Go to 'Phone' settings and set ShieldInfo as Caller ID & Spam app",
                Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Toast.makeText(this,
                "Go to Phone Settings → Caller ID & Spam → choose ShieldInfo SIM Box",
                Toast.LENGTH_LONG).show()
        }
    }

    private fun tryAutoDetectSimNumber() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            == PackageManager.PERMISSION_GRANTED) {
            try {
                val tm = getSystemService(TelephonyManager::class.java)
                val line = tm?.line1Number
                if (!line.isNullOrBlank()) {
                    val formatted = if (line.startsWith("+")) line
                                    else "+91${line.trimStart('0')}"
                    etSimNumber.setText(formatted)
                }
            } catch (e: Exception) {
                // Not available on all devices — user enters manually
            }
        }
    }

    private fun setStatus(msg: String, green: Boolean) {
        tvStatus.text = msg
        tvStatus.setTextColor(
            if (green) getColor(android.R.color.holo_green_dark)
            else       getColor(android.R.color.holo_red_dark)
        )
    }

    private fun checkAndRequestPermissions() {
        val missing = REQUIRED_PERMISSIONS.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (!allGranted) {
                setStatus("⚠️ SMS permission required — please grant it in Settings", green = false)
            }
        }
    }
}
