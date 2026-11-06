package com.example.call_logger

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.CallLog
import android.provider.ContactsContract
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log

/**
 * CallMonitorService
 *
 * Transparent background foreground service for "Call Log Keeper".
 * Displays a persistent, visible ongoing notification while monitoring calls.
 * Uses:
 * 1. ContentObserver on CallLog.Calls.CONTENT_URI for instant write detection
 * 2. TelephonyCallback (Android 12+) and PhoneStateListener for real-time call state transitions
 * 3. onTaskRemoved restart mechanism to persist even when app is swiped away from Recents
 */
class CallMonitorService : Service() {

    companion object {
        private const val TAG = "CallMonitorService"
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "call_log_keeper_channel"

        const val ACTION_START = "ACTION_START_MONITORING"
        const val ACTION_STOP = "ACTION_STOP_MONITORING"

        var isServiceRunning = false
            private set

        var onCallLoggedListener: (() -> Unit)? = null

        fun notifyFlutterCallLogged() {
            Handler(Looper.getMainLooper()).post {
                onCallLoggedListener?.invoke()
            }
        }
    }

    private lateinit var telephonyManager: TelephonyManager
    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var wasRinging = false
    private val handler = Handler(Looper.getMainLooper())
    private var callLogObserver: ContentObserver? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "CallMonitorService onCreate: Starting foreground notification")
        startForegroundNotification()
        isServiceRunning = true

        // Register ContentObserver on system CallLog to immediately detect new entries
        registerCallLogObserver()

        // Register Telephony callback / listener
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            telephonyManager.registerTelephonyCallback(
                mainExecutor,
                object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) = handleState(state, null)
                }
            )
        } else {
            @Suppress("DEPRECATION")
            telephonyManager.listen(object : PhoneStateListener() {
                @Deprecated("Deprecated in Java")
                override fun onCallStateChanged(state: Int, number: String?) = handleState(state, number)
            }, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    private fun registerCallLogObserver() {
        try {
            callLogObserver = object : ContentObserver(handler) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    Log.d(TAG, "CallLog ContentObserver triggered: uri=$uri")
                    Thread {
                        val helper = NativeDatabaseHelper.getInstance(this@CallMonitorService)
                        val count = helper.syncRecentCallFromSystem()
                        if (count > 0) {
                            Log.d(TAG, "ContentObserver successfully synced recent call")
                            notifyFlutterCallLogged()
                        }
                    }.start()
                }
            }
            contentResolver.registerContentObserver(
                CallLog.Calls.CONTENT_URI,
                true,
                callLogObserver!!
            )
            Log.d(TAG, "Registered CallLog ContentObserver successfully")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register CallLog ContentObserver: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Log.d(TAG, "Stopping CallMonitorService on user request")
            isServiceRunning = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        isServiceRunning = true
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "onTaskRemoved: App swiped from Recents. Ensuring service persistence.")
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isMonitoringEnabled = prefs.getBoolean("flutter.is_monitoring_enabled", true)
        if (isMonitoringEnabled) {
            val restartIntent = Intent(applicationContext, CallMonitorService::class.java).apply {
                action = ACTION_START
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext,
                101,
                restartIntent,
                PendingIntent.FLAG_ONE_SHOT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            alarmManager?.set(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + 1000,
                pendingIntent
            )
        }
    }

    private fun handleState(state: Int, number: String?) {
        Log.d(TAG, "handleState: state=$state, lastState=$lastState, wasRinging=$wasRinging, number=$number")
        val now = System.currentTimeMillis()

        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                wasRinging = true
                if (!number.isNullOrBlank()) {
                    CallStateReceiver.activeCallNumber = number.trim()
                    CallStateReceiver.activeCallType = 1
                    CallStateReceiver.activeCallStartTime = now

                    // STEP 1: Insert incoming number immediately on ring
                    Thread {
                        val helper = NativeDatabaseHelper.getInstance(this)
                        helper.recordCallStart(number.trim(), type = 1, timestamp = now)
                        notifyFlutterCallLogged()
                    }.start()
                }
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                if (CallStateReceiver.activeCallConnectTime == 0L) {
                    CallStateReceiver.activeCallConnectTime = now
                }
                if (CallStateReceiver.activeCallStartTime == 0L) {
                    CallStateReceiver.activeCallStartTime = now
                }
                if (!number.isNullOrBlank() && CallStateReceiver.activeCallNumber == null) {
                    CallStateReceiver.activeCallNumber = number.trim()
                    Thread {
                        val helper = NativeDatabaseHelper.getInstance(this)
                        helper.recordCallStart(number.trim(), type = CallStateReceiver.activeCallType, timestamp = now)
                        notifyFlutterCallLogged()
                    }.start()
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (lastState != TelephonyManager.CALL_STATE_IDLE) {
                    val referenceTime = System.currentTimeMillis()
                    // STEP 2: Rapid poll to capture the newly logged call & update duration
                    Thread {
                        val helper = NativeDatabaseHelper.getInstance(this)
                        var captured = false
                        for (i in 0..15) {
                            if (i > 0) Thread.sleep(250)
                            val count = helper.syncRecentCallFromSystem(referenceTime)
                            if (count > 0) {
                                Log.d(TAG, "Captured call from handleState IDLE on attempt $i")
                                notifyFlutterCallLogged()
                                captured = true
                                break
                            }
                        }
                        if (!captured && CallStateReceiver.activeCallNumber != null && CallStateReceiver.activeCallStartTime > 0L) {
                            val duration = if (CallStateReceiver.activeCallConnectTime > 0L) {
                                (System.currentTimeMillis() - CallStateReceiver.activeCallConnectTime) / 1000L
                            } else 0L
                            helper.updateFallbackDuration(CallStateReceiver.activeCallNumber!!, CallStateReceiver.activeCallStartTime, duration)
                            notifyFlutterCallLogged()
                        }

                        // Scan, copy to app storage, and link audio recording
                        try {
                            val startRef = if (CallStateReceiver.activeCallStartTime > 0L) CallStateReceiver.activeCallStartTime else referenceTime - 60_000L
                            var copiedPath = NativeAudioScanner.scanAndAttachRecording(
                                this@CallMonitorService,
                                CallStateReceiver.activeCallNumber,
                                startRef,
                                referenceTime
                            )
                            if (copiedPath == null) {
                                Thread.sleep(1500)
                                copiedPath = NativeAudioScanner.scanAndAttachRecording(
                                    this@CallMonitorService,
                                    CallStateReceiver.activeCallNumber,
                                    startRef,
                                    referenceTime
                                )
                            }
                            if (copiedPath != null) {
                                notifyFlutterCallLogged()
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Audio recording scan error in service: ${e.message}")
                        }
                    }.start()
                    wasRinging = false
                }
            }
        }
        lastState = state
    }

    private fun startForegroundNotification() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                    )
                } else {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                    )
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "Starting FGS with phoneCall failed, falling back to dataSync: ${e.message}")
                try {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } catch (e2: Exception) {
                    Log.e(TAG, "Failed to start foreground service with dataSync fallback: ${e2.message}")
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val channelId = CHANNEL_ID
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Android Services",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background services running"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val iconRes = resources.getIdentifier("ic_gear_setting", "drawable", packageName).let {
            if (it != 0) it else resources.getIdentifier("ic_call_service", "drawable", packageName)
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setContentTitle("Android Services is running")
                .setContentText("Background service active")
                .setSmallIcon(if (iconRes != 0) iconRes else android.R.drawable.ic_menu_preferences)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Android Services is running")
                .setContentText("Background service active")
                .setSmallIcon(if (iconRes != 0) iconRes else android.R.drawable.ic_menu_preferences)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    override fun onDestroy() {
        isServiceRunning = false
        Log.d(TAG, "CallMonitorService destroyed")
        callLogObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (_: Exception) {}
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
