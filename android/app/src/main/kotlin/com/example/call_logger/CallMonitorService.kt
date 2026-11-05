package com.example.call_logger

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
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
 * Uses TelephonyCallback (Android 12+) and PhoneStateListener to detect call end,
 * then syncs the confirmed call record from system CallLog.Calls into SQLite.
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

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "CallMonitorService onCreate: Starting foreground notification")
        startForeground(NOTIFICATION_ID, buildNotification())
        isServiceRunning = true

        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            telephonyManager.registerTelephonyCallback(
                mainExecutor,
                object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) = handleState(state)
                }
            )
        } else {
            @Suppress("DEPRECATION")
            telephonyManager.listen(object : PhoneStateListener() {
                @Deprecated("Deprecated in Java")
                override fun onCallStateChanged(state: Int, number: String?) = handleState(state)
            }, PhoneStateListener.LISTEN_CALL_STATE)
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

    private fun handleState(state: Int) {
        Log.d(TAG, "handleState: state=$state, lastState=$lastState, wasRinging=$wasRinging")
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                wasRinging = true
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                /* Call answered or outgoing in progress */
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (lastState != TelephonyManager.CALL_STATE_IDLE) {
                    val answered = wasRinging
                    // Standard delay (~800ms) for Android system CallLog.Calls to populate
                    handler.postDelayed({
                        syncLatestCallFromLog(answered)
                        wasRinging = false
                    }, 800)
                }
            }
        }
        lastState = state
    }

    /**
     * Reads the confirmed call record after it ends and saves it to local SQLite.
     */
    private fun syncLatestCallFromLog(wasAnswered: Boolean) {
        try {
            val cursor = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                null,
                null,
                null,
                "${CallLog.Calls.DATE} DESC LIMIT 1"
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    val number = it.getString(it.getColumnIndexOrThrow(CallLog.Calls.NUMBER))
                    val type = it.getInt(it.getColumnIndexOrThrow(CallLog.Calls.TYPE))
                    val duration = it.getLong(it.getColumnIndexOrThrow(CallLog.Calls.DURATION))
                    val date = it.getLong(it.getColumnIndexOrThrow(CallLog.Calls.DATE))
                    val name = resolveContactName(number)

                    NativeDatabaseHelper(this).insertCallRecord(number, name, type, date, duration)
                    Log.d(TAG, "Synced latest call to backup: number=$number, name=$name, type=$type, date=$date, duration=$duration")
                    notifyFlutterCallLogged()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing latest call from log: ${e.message}", e)
        }
    }

    /**
     * Resolves contact display name from ContactsContract by phone number.
     */
    private fun resolveContactName(number: String): String? {
        if (number.isBlank()) return null
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number.trim()))
            contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not resolve contact name: ${e.message}")
            null
        }
    }

    /**
     * Builds the transparent, persistent, visible ongoing notification.
     */
    private fun buildNotification(): Notification {
        val channelId = CHANNEL_ID
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Call Log Keeper",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitoring calls to keep your backup up to date"
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

        val iconRes = resources.getIdentifier("ic_call_service", "drawable", packageName).let {
            if (it != 0) it else android.R.drawable.sym_call_incoming
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setContentTitle("Call Log Keeper is running")
                .setContentText("Monitoring calls to keep your backup up to date")
                .setSmallIcon(iconRes)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Call Log Keeper is running")
                .setContentText("Monitoring calls to keep your backup up to date")
                .setSmallIcon(iconRes)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    override fun onDestroy() {
        isServiceRunning = false
        Log.d(TAG, "CallMonitorService destroyed")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
