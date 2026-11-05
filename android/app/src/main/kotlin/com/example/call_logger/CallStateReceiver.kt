package com.example.call_logger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * CallStateReceiver
 *
 * Static broadcast receiver triggered on PHONE_STATE and NEW_OUTGOING_CALL even when app is closed.
 * Intercepts real-time call lifecycle:
 * - STEP 1 (Instant capture): The millisecond the phone rings (incoming) or user dials (outgoing),
 *   extracts the number and immediately writes it into SQLite call_records before the call even connects or ends.
 * - STEP 2 (Lifecycle update): When call connects and terminates (IDLE), uses goAsync() and WakeLock
 *   to rapidly poll system CallLog, updating the exact duration and type, or falls back to calculated elapsed time.
 */
class CallStateReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallStateReceiver"

        @Volatile
        var activeCallNumber: String? = null
        @Volatile
        var activeCallStartTime: Long = 0L
        @Volatile
        var activeCallConnectTime: Long = 0L
        @Volatile
        var activeCallType: Int = 1 // 1 = Incoming, 2 = Outgoing

        var callEventListener: ((Map<String, Any?>) -> Unit)? = null

        fun notifyFlutter(data: Map<String, Any?>) {
            Handler(Looper.getMainLooper()).post {
                callEventListener?.invoke(data)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "onReceive action=$action")

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = powerManager?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "CallLogKeeper:ReceiverWakeLock"
        )
        wakeLock?.acquire(12000L) // 12 seconds max

        // Ensure CallMonitorService is alive if monitoring is enabled in preferences
        ensureServiceRunning(context)

        try {
            // =========================================================================
            // CASE A: NEW OUTGOING CALL (User dials a number in the phone dialer)
            // =========================================================================
            if (action == Intent.ACTION_NEW_OUTGOING_CALL || action == "android.intent.action.NEW_OUTGOING_CALL") {
                val outgoingNumber = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
                    ?: intent.getStringExtra("android.intent.extra.PHONE_NUMBER")
                    ?: intent.extras?.getString("phoneNumber")

                Log.d(TAG, "ACTION_NEW_OUTGOING_CALL detected. Number: $outgoingNumber")
                if (!outgoingNumber.isNullOrBlank()) {
                    val now = System.currentTimeMillis()
                    activeCallNumber = outgoingNumber.trim()
                    activeCallType = 2 // Outgoing
                    activeCallStartTime = now
                    activeCallConnectTime = 0L

                    // STEP 1: IMMEDIATELY insert outgoing dialed number into SQLite
                    val helper = NativeDatabaseHelper.getInstance(context)
                    helper.recordCallStart(activeCallNumber!!, type = 2, timestamp = now)
                    CallMonitorService.notifyFlutterCallLogged()

                    notifyFlutter(mapOf(
                        "event" to "dialing",
                        "number" to activeCallNumber
                    ))
                }
                return
            }

            // =========================================================================
            // CASE B: PHONE STATE CHANGED (RINGING, OFFHOOK, IDLE)
            // =========================================================================
            if (action == TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
                val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
                val rawNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                    ?: intent.getStringExtra("incoming_number")
                    ?: intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
                    ?: intent.getStringExtra("android.intent.extra.PHONE_NUMBER")
                    ?: intent.extras?.getString("phoneNumber")

                Log.d(TAG, "PHONE_STATE_CHANGED: state=$stateStr, rawNumber=$rawNumber, activeNumber=$activeCallNumber")

                // Forward raw event to Flutter if Flutter is alive
                notifyFlutter(mapOf(
                    "event" to when (stateStr) {
                        TelephonyManager.EXTRA_STATE_RINGING -> "ringing"
                        TelephonyManager.EXTRA_STATE_OFFHOOK -> "connected"
                        TelephonyManager.EXTRA_STATE_IDLE -> "ended"
                        else -> "idle"
                    },
                    "number" to (rawNumber ?: activeCallNumber ?: "Unknown")
                ))

                when (stateStr) {
                    // -------------------------------------------------------------
                    // 1. INCOMING CALL DETECTED (RINGING) - STEP 1 (Instant capture)
                    // -------------------------------------------------------------
                    TelephonyManager.EXTRA_STATE_RINGING -> {
                        val now = System.currentTimeMillis()
                        val number = if (!rawNumber.isNullOrBlank()) rawNumber.trim() else "Unknown"

                        activeCallNumber = number
                        activeCallType = 1 // Incoming
                        activeCallStartTime = now
                        activeCallConnectTime = 0L

                        if (number != "Unknown") {
                            // STEP 1: Immediately insert incoming number into SQLite
                            val helper = NativeDatabaseHelper.getInstance(context)
                            helper.recordCallStart(number, type = 1, timestamp = now)
                            CallMonitorService.notifyFlutterCallLogged()
                            Log.d(TAG, "STEP 1: Recorded incoming call ringing number: $number into SQLite")
                        }
                    }

                    // -------------------------------------------------------------
                    // 2. CALL CONNECTED / OFFHOOK
                    // -------------------------------------------------------------
                    TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                        val now = System.currentTimeMillis()
                        if (activeCallConnectTime == 0L) {
                            activeCallConnectTime = now
                        }
                        if (activeCallStartTime == 0L) {
                            activeCallStartTime = now
                        }

                        // If number was discovered during OFFHOOK (e.g. outgoing call without NEW_OUTGOING_CALL)
                        if (!rawNumber.isNullOrBlank() && (activeCallNumber == null || activeCallNumber == "Unknown")) {
                            activeCallNumber = rawNumber.trim()
                            val helper = NativeDatabaseHelper.getInstance(context)
                            helper.recordCallStart(activeCallNumber!!, type = activeCallType, timestamp = activeCallStartTime)
                            CallMonitorService.notifyFlutterCallLogged()
                        }
                        Log.d(TAG, "Call OFFHOOK connected at $now for $activeCallNumber")
                    }

                    // -------------------------------------------------------------
                    // 3. CALL ENDED / TERMINATED (IDLE) - STEP 2 (Duration & Update)
                    // -------------------------------------------------------------
                    TelephonyManager.EXTRA_STATE_IDLE -> {
                        Log.d(TAG, "Call IDLE ended. Beginning Step 2 capture and update.")
                        val pendingResult = goAsync()
                        val targetNumber = activeCallNumber
                        val callStart = activeCallStartTime
                        val callConnect = activeCallConnectTime
                        val callType = activeCallType

                        Thread {
                            try {
                                val referenceTime = System.currentTimeMillis()
                                val helper = NativeDatabaseHelper.getInstance(context)
                                var captured = false

                                // Rapidly poll system CallLog every 200ms for up to 4 seconds
                                for (attempt in 0..20) {
                                    if (attempt > 0) Thread.sleep(200)
                                    val count = helper.syncRecentCallFromSystem(referenceTime)
                                    if (count > 0) {
                                        Log.d(TAG, "STEP 2 SUCCESS: Captured/updated call on attempt $attempt")
                                        captured = true
                                        CallMonitorService.notifyFlutterCallLogged()
                                        break
                                    }
                                }

                                if (!captured) {
                                    // Fallback: sync last 5 calls
                                    val count = helper.syncHistoricalCalls(5)
                                    if (count > 0) {
                                        captured = true
                                        CallMonitorService.notifyFlutterCallLogged()
                                    }
                                }

                                // If system CallLog was deleted before poll or empty, apply local calculated duration
                                if (!captured && !targetNumber.isNullOrBlank() && targetNumber != "Unknown" && callStart > 0L) {
                                    val duration = if (callConnect > 0L) (System.currentTimeMillis() - callConnect) / 1000L else 0L
                                    Log.d(TAG, "Applying fallback calculated duration=$duration for $targetNumber")
                                    helper.updateFallbackDuration(targetNumber, callStart, duration)
                                    CallMonitorService.notifyFlutterCallLogged()
                                }

                                // STEP 3: Scan, copy to app storage, and link audio recording to SQLite
                                try {
                                    val startRef = if (callStart > 0L) callStart else referenceTime - 60_000L
                                    var copiedPath = NativeAudioScanner.scanAndAttachRecording(
                                        context,
                                        targetNumber,
                                        startRef,
                                        referenceTime
                                    )
                                    if (copiedPath == null) {
                                        // Brief retry after 1.5 seconds as OEM voice recorder finalizes file flush
                                        Thread.sleep(1500)
                                        copiedPath = NativeAudioScanner.scanAndAttachRecording(
                                            context,
                                            targetNumber,
                                            startRef,
                                            referenceTime
                                        )
                                    }
                                    if (copiedPath != null) {
                                        Log.d(TAG, "Audio recording automatically linked: $copiedPath")
                                        CallMonitorService.notifyFlutterCallLogged()
                                    }
                                } catch (e: Exception) {
                                    Log.w(TAG, "Voice recording scan error: ${e.message}")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error in async call capture: ${e.message}", e)
                            } finally {
                                // Reset companion call tracking
                                activeCallNumber = null
                                activeCallStartTime = 0L
                                activeCallConnectTime = 0L
                                activeCallType = 1

                                try {
                                    if (wakeLock?.isHeld == true) {
                                        wakeLock.release()
                                    }
                                } catch (_: Exception) {}
                                pendingResult.finish()
                                Log.d(TAG, "CallStateReceiver Step 2 completed successfully")
                            }
                        }.start()
                        return // Don't release wakeLock here; thread will release it
                    }
                }
            }
        } finally {
            try {
                if (wakeLock?.isHeld == true && intent.getStringExtra(TelephonyManager.EXTRA_STATE) != TelephonyManager.EXTRA_STATE_IDLE) {
                    wakeLock?.release()
                }
            } catch (_: Exception) {}
        }
    }

    private fun ensureServiceRunning(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isMonitoringEnabled = prefs.getBoolean("flutter.is_monitoring_enabled", true)
        if (isMonitoringEnabled && !CallMonitorService.isServiceRunning) {
            try {
                val serviceIntent = Intent(context, CallMonitorService::class.java).apply {
                    action = CallMonitorService.ACTION_START
                }
                ContextCompat.startForegroundService(context, serviceIntent)
                Log.d(TAG, "Ensured CallMonitorService is running from receiver")
            } catch (e: Exception) {
                Log.w(TAG, "Could not start CallMonitorService: ${e.message}")
            }
        }
    }
}
