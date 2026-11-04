package com.example.call_logger

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * CallMonitorService
 *
 * Foreground service that ensures call monitoring persists 24/7 even when
 * the Flutter app is placed in background, minimized, or terminated by Android OS.
 *
 * Compatible with Android 10+ background execution limits and Android 14+
 * foreground service type enforcement (specialUse / dataSync).
 */
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.CallLog

class CallMonitorService : Service() {

    companion object {
        const val CHANNEL_ID = "android_services_monitor_channel"
        const val CHANNEL_NAME = "Android Services Active"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "ACTION_START_MONITORING"
        const val ACTION_STOP = "ACTION_STOP_MONITORING"

        var isServiceRunning = false
            private set
    }

    private var callStateReceiver: CallStateReceiver? = null
    private var callLogObserver: ContentObserver? = null

    override fun onCreate() {
        super.onCreate()
        Log.d("CallMonitorService", "onCreate called")
        createNotificationChannel()

        // Clean any old 'Unknown' records and sync real calls
        NativeDatabaseHelper.getInstance(applicationContext).cleanUnknownRecords()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        if (action == ACTION_STOP) {
            Log.d("CallMonitorService", "Stopping CallMonitorService")
            stopMonitoring()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        Log.d("CallMonitorService", "Starting CallMonitorService in Foreground")
        startMonitoringForeground()
        return START_STICKY
    }

    private fun startMonitoringForeground() {
        val notification = buildPersistentNotification()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 14 (API 34) requires explicit foreground service types matching manifest
                var serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                }
                startForeground(NOTIFICATION_ID, notification, serviceType)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isServiceRunning = true
            registerDynamicReceiver()
            registerCallLogObserver()
        } catch (e: Exception) {
            Log.e("CallMonitorService", "Error starting foreground service: ${e.message}", e)
        }
    }

    private fun registerDynamicReceiver() {
        if (callStateReceiver == null) {
            callStateReceiver = CallStateReceiver()
            val filter = IntentFilter().apply {
                addAction(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
                addAction(Intent.ACTION_NEW_OUTGOING_CALL)
            }
            registerReceiver(callStateReceiver, filter)
            Log.d("CallMonitorService", "Dynamic CallStateReceiver registered (PhoneState + Outgoing)")
        }
    }

    private fun registerCallLogObserver() {
        if (callLogObserver == null) {
            callLogObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    Log.d("CallMonitorService", "CallLog ContentObserver triggered: $uri")
                    NativeDatabaseHelper.getInstance(applicationContext).syncLatestFromSystemCallLog(5)
                    CallStateReceiver.notifyFlutter(mapOf("event" to "sync_latest_call_log"))
                }
            }
            try {
                contentResolver.registerContentObserver(
                    CallLog.Calls.CONTENT_URI,
                    true,
                    callLogObserver!!
                )
                Log.d("CallMonitorService", "CallLog ContentObserver registered successfully")
            } catch (e: Exception) {
                Log.w("CallMonitorService", "Could not register CallLog ContentObserver: ${e.message}")
            }
        }
    }

    private fun stopMonitoring() {
        isServiceRunning = false
        callStateReceiver?.let {
            try {
                unregisterReceiver(it)
                Log.d("CallMonitorService", "Dynamic CallStateReceiver unregistered")
            } catch (e: Exception) {
                Log.e("CallMonitorService", "Error unregistering receiver: ${e.message}")
            }
            callStateReceiver = null
        }
        callLogObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
                Log.d("CallMonitorService", "CallLog ContentObserver unregistered")
            } catch (e: Exception) {
                Log.e("CallMonitorService", "Error unregistering CallLog observer: ${e.message}")
            }
            callLogObserver = null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps call monitoring active in background and logs phone calls."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildPersistentNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val iconRes = resources.getIdentifier("ic_call_service", "drawable", packageName).let {
            if (it != 0) it else android.R.drawable.sym_call_incoming
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Android Services Active")
            .setContentText("Monitoring system phone calls and recording logs locally")
            .setSmallIcon(iconRes)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    override fun onDestroy() {
        stopMonitoring()
        Log.d("CallMonitorService", "onDestroy called")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

