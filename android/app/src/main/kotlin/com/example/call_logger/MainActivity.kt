package com.example.call_logger

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity
 *
 * Configures Flutter MethodChannel communication for:
 * - Starting and stopping CallMonitorService foreground service
 * - Querying hardware device/SIM phone number via SubscriptionManager / TelephonyManager
 * - Forwarding real-time call lifecycle events from CallStateReceiver into Flutter Dart engine
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.call_logger/monitor"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitoring" -> {
                    val success = startCallMonitorService()
                    result.success(success)
                }

                "stopMonitoring" -> {
                    val success = stopCallMonitorService()
                    result.success(success)
                }

                "isMonitoringActive" -> {
                    result.success(CallMonitorService.isServiceRunning)
                }

                "getDevicePhoneNumber" -> {
                    val number = getDevicePhoneNumber()
                    result.success(number)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // Connect receiver callback to invoke Flutter method channel
        CallStateReceiver.callEventListener = { eventData ->
            runOnUiThread {
                methodChannel?.invokeMethod("onCallEvent", eventData)
            }
        }
    }

    private fun startCallMonitorService(): Boolean {
        return try {
            val intent = Intent(this, CallMonitorService::class.java).apply {
                action = CallMonitorService.ACTION_START
            }
            ContextCompat.startForegroundService(this, intent)

            // Save flag in SharedPreferences
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.is_monitoring_enabled", true).apply()
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to start CallMonitorService: ${e.message}", e)
            false
        }
    }

    private fun stopCallMonitorService(): Boolean {
        return try {
            val intent = Intent(this, CallMonitorService::class.java).apply {
                action = CallMonitorService.ACTION_STOP
            }
            startService(intent)

            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.is_monitoring_enabled", false).apply()
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to stop CallMonitorService: ${e.message}", e)
            false
        }
    }

    /**
     * Query hardware line 1 phone number from SubscriptionManager or TelephonyManager.
     * Note: Many Android carriers do not store line 1 number on the SIM card, so it
     * may legitimately return null or empty string. The Flutter layer falls back to
     * user-entered number in Settings.
     */
    private fun getDevicePhoneNumber(): String? {
        val hasState = ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
        val hasNumbers = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_NUMBERS) == PackageManager.PERMISSION_GRANTED
        } else true

        if (!hasState && !hasNumbers) {
            Log.w("MainActivity", "Lacking READ_PHONE_STATE or READ_PHONE_NUMBERS to query device number")
            return null
        }

        try {
            // First attempt: SubscriptionManager (dual-SIM and modern Android friendly)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                val activeList = sm?.activeSubscriptionInfoList
                if (!activeList.isNullOrEmpty()) {
                    for (info in activeList) {
                        val number = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            sm.getPhoneNumber(info.subscriptionId)
                        } else {
                            @Suppress("DEPRECATION")
                            info.number
                        }
                        if (!number.isNullOrBlank()) {
                            return number.trim()
                        }
                    }
                }
            }

            // Second attempt: TelephonyManager line1Number
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            @Suppress("DEPRECATION")
            val line1 = tm?.line1Number
            if (!line1.isNullOrBlank()) {
                return line1.trim()
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error reading phone number: ${e.message}", e)
        }

        return null
    }

    override fun onDestroy() {
        CallStateReceiver.callEventListener = null
        super.onDestroy()
    }
}

