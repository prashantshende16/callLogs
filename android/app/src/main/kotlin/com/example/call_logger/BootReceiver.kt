package com.example.call_logger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * BootReceiver
 *
 * Automatically restarts the CallMonitorService after device reboot (BOOT_COMPLETED)
 * if monitoring was previously enabled by the user in app settings.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d("BootReceiver", "Received broadcast action: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON") {

            // Check if user enabled monitoring previously in Flutter SharedPreferences
            // Flutter SharedPreferences writes to "FlutterSharedPreferences" xml file with prefix "flutter."
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isMonitoringEnabled = flutterPrefs.getBoolean("flutter.is_monitoring_enabled", true)

            Log.d("BootReceiver", "isMonitoringEnabled from preferences = $isMonitoringEnabled")

            if (isMonitoringEnabled) {
                val serviceIntent = Intent(context, CallMonitorService::class.java).apply {
                    this.action = CallMonitorService.ACTION_START
                }

                try {
                    ContextCompat.startForegroundService(context, serviceIntent)
                    Log.d("BootReceiver", "CallMonitorService started successfully on boot")
                } catch (e: Exception) {
                    Log.e("BootReceiver", "Failed to start CallMonitorService on boot: ${e.message}", e)
                }
            }
        }
    }
}

