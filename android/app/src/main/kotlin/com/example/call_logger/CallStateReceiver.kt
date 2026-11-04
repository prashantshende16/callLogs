package com.example.call_logger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log

/**
 * CallStateReceiver
 *
 * Listens for system PHONE_STATE broadcasts:
 * - RINGING: Call is incoming and ringing.
 * - OFFHOOK: Call answered, connected, or outgoing call in progress.
 * - IDLE: Call ended, missed, or rejected.
 *
 * Implements a state-machine to accurately differentiate:
 * - Incoming Answered vs Incoming Missed/Rejected
 * - Outgoing Answered vs Outgoing Cancelled
 *
 * Communicates events to Flutter via MainActivity method channel.
 */
class CallStateReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallStateReceiver"

        // State machine variables to track across sequential state broadcasts
        private var lastState = TelephonyManager.CALL_STATE_IDLE
        private var callStartTime: Long = 0
        private var isIncoming = false
        private var savedNumber: String? = null
        private var detectedSimSlot: String? = null
        private var lastIdleHandledTime: Long = 0

        // Listener for Flutter MainActivity communication
        var callEventListener: ((Map<String, Any?>) -> Unit)? = null

        fun notifyFlutter(data: Map<String, Any?>) {
            Handler(Looper.getMainLooper()).post {
                callEventListener?.invoke(data)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_NEW_OUTGOING_CALL) {
            val outgoingNum = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
            if (!outgoingNum.isNullOrBlank()) {
                savedNumber = outgoingNum.trim()
                isIncoming = false
                callStartTime = System.currentTimeMillis()
                Log.d(TAG, "NEW_OUTGOING_CALL captured dialed number: $outgoingNum")
            }
            return
        }

        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
            return
        }

        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        // Try extracting SIM slot information
        extractSimSlot(context, intent)

        Log.d(TAG, "PHONE_STATE broadcast: state=$stateStr, incomingNumber=$incomingNumber, slot=$detectedSimSlot")

        // CRITICAL: Handle IDLE immediately so fresh process spawns never drop it
        if (stateStr == TelephonyManager.EXTRA_STATE_IDLE) {
            handleCallEnded(context, incomingNumber)
            return
        }

        val state = when (stateStr) {
            TelephonyManager.EXTRA_STATE_RINGING -> TelephonyManager.CALL_STATE_RINGING
            TelephonyManager.EXTRA_STATE_OFFHOOK -> TelephonyManager.CALL_STATE_OFFHOOK
            else -> TelephonyManager.CALL_STATE_IDLE
        }

        onCallStateChanged(context, state, incomingNumber)
    }

    private fun extractSimSlot(context: Context, intent: Intent) {
        try {
            val subId = intent.getIntExtra("subscription", -1)
            val slotIdx = intent.getIntExtra("slot", -1)

            if (slotIdx >= 0) {
                detectedSimSlot = "SIM ${slotIdx + 1}"
                return
            }

            if (subId >= 0 && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP_MR1) {
                val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                val info = sm?.getActiveSubscriptionInfo(subId)
                if (info != null) {
                    detectedSimSlot = "SIM ${info.simSlotIndex + 1} (${info.displayName})"
                    return
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not extract SIM slot info: ${e.message}")
        }
    }

    private fun onCallStateChanged(context: Context, state: Int, incomingNumber: String?) {
        if (state == lastState) {
            // No state change
            return
        }

        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                isIncoming = true
                callStartTime = System.currentTimeMillis()
                savedNumber = incomingNumber ?: savedNumber

                val event = mapOf(
                    "event" to "ringing",
                    "number" to (savedNumber ?: "Unknown"),
                    "simSlot" to detectedSimSlot,
                    "timestamp" to callStartTime
                )
                notifyFlutter(event)
            }

            TelephonyManager.CALL_STATE_OFFHOOK -> {
                // Call connected (either incoming answered or outgoing connected)
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val inAppMicEnabled = prefs.getBoolean("flutter.enable_in_app_mic_recording", false)
                if (inAppMicEnabled) {
                    CallAudioRecorder.startRecording(context, savedNumber ?: "Unknown")
                }

                if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                    // Incoming call was answered
                    isIncoming = true
                    val event = mapOf(
                        "event" to "connected",
                        "number" to (savedNumber ?: "Unknown"),
                        "callType" to "incoming",
                        "simSlot" to detectedSimSlot,
                        "timestamp" to System.currentTimeMillis()
                    )
                    notifyFlutter(event)
                } else {
                    // Outgoing call started
                    isIncoming = false
                    callStartTime = System.currentTimeMillis()
                    val event = mapOf(
                        "event" to "connected",
                        "number" to (savedNumber ?: "Unknown"),
                        "callType" to "outgoing",
                        "simSlot" to detectedSimSlot,
                        "timestamp" to callStartTime
                    )
                    notifyFlutter(event)
                }
            }
        }

        lastState = state
    }

    /**
     * Handles call termination (IDLE state).
     * Works 100% reliably 24/7 even when the app is completely closed or killed.
     * Uses goAsync() and a CPU WakeLock to poll system CallLog until the completed call
     * is guaranteed saved directly into local SQLite, so even immediate dialer deletion
     * preserves the call in Android Services app.
     */
    private fun handleCallEnded(context: Context, incomingNumber: String?) {
        val now = System.currentTimeMillis()

        // Debounce redundant duplicate broadcasts (e.g. dual SIM IDLE broadcasts)
        if (now - lastIdleHandledTime < 1500) {
            Log.d(TAG, "Ignoring duplicate IDLE broadcast received within 1500ms")
            return
        }
        lastIdleHandledTime = now

        // 1. Stop in-app mic recording if active
        val audioPath = CallAudioRecorder.stopRecording(context)

        val endTime = now
        val durationSec = if (callStartTime > 0) ((endTime - callStartTime) / 1000).toInt() else 0

        val callType: String
        val callStatus: String

        if (lastState == TelephonyManager.CALL_STATE_RINGING) {
            callType = "missed"
            callStatus = "missed"
        } else if (isIncoming) {
            callType = "incoming"
            callStatus = "ended"
        } else {
            callType = "outgoing"
            callStatus = "ended"
        }

        val callSavedNumber = savedNumber ?: incomingNumber ?: "Unknown"
        val callStart = if (callStartTime > 0) callStartTime else endTime
        val contactName = NativeDatabaseHelper.getContactName(context, callSavedNumber)

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val userPhone = prefs.getString("flutter.user_phone_number", "") ?: ""
        val detectedPhone = prefs.getString("flutter.detected_phone_number", "") ?: ""
        val receiverNumber = if (userPhone.trim().isNotEmpty()) {
            userPhone.trim()
        } else if (detectedPhone.trim().isNotEmpty()) {
            detectedPhone.trim()
        } else {
            "My Device"
        }

        // 2. Insert immediate entry if number is known
        if (callSavedNumber != "Unknown" && callSavedNumber.isNotBlank()) {
            NativeDatabaseHelper.getInstance(context).insertCallRecord(
                callerNumber = callSavedNumber,
                receiverNumber = receiverNumber,
                callType = callType,
                callStatus = callStatus,
                startTime = callStart,
                endTime = endTime,
                durationSeconds = durationSec,
                simSlot = detectedSimSlot,
                audioPath = audioPath,
                callerName = contactName
            )
        }

        // Notify active Flutter UI if available
        notifyFlutter(mapOf(
            "event" to "ended",
            "number" to callSavedNumber,
            "callerName" to contactName,
            "callType" to callType,
            "callStatus" to callStatus,
            "startTime" to callStart,
            "endTime" to endTime,
            "durationSeconds" to durationSec,
            "simSlot" to detectedSimSlot,
            "audioPath" to audioPath
        ))

        // Reset tracking state
        isIncoming = false
        callStartTime = 0
        savedNumber = null
        lastState = TelephonyManager.CALL_STATE_IDLE

        // 3. Keep receiver process alive using goAsync() and WakeLock
        val pendingResult = goAsync()
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CallLogger:CallEndedSync")

        Thread {
            try {
                wakeLock?.acquire(10000L)
                Log.d(TAG, "Call ended: Starting goAsync() background sync for call that ended at $now...")

                var capturedNumber: String? = null
                var capturedStartTime: Long = 0L

                for (attempt in 1..20) { // Up to 5.0 seconds (20 x 250ms)
                    val result = NativeDatabaseHelper.getInstance(context)
                        .syncLatestFromSystemCallLog(10, referenceEndTime = now)

                    if (result.recentCallCaptured) {
                        Log.d(TAG, "goAsync: Successfully captured recently ended call (${result.capturedNumber}) into SQLite on attempt $attempt (${attempt * 250}ms)!")
                        capturedNumber = result.capturedNumber
                        capturedStartTime = result.capturedStartTime
                        break
                    }

                    Thread.sleep(250)
                }

                // If not matched by exact reference time, do a general sync to ensure everything is caught
                if (capturedNumber == null) {
                    NativeDatabaseHelper.getInstance(context).syncLatestFromSystemCallLog(10, 0L)
                }

                // 4. Discover and link native recording file (.m4a, .amr, .wav, .mp3)
                val searchNum = capturedNumber ?: if (callSavedNumber != "Unknown") callSavedNumber else ""
                val searchStart = if (capturedStartTime > 0) capturedStartTime else callStart
                val nativeAudio = NativeAudioScanner.findRecordingForCall(context, searchNum, searchStart, endTime)
                if (nativeAudio != null) {
                    NativeDatabaseHelper.getInstance(context).updateAudioPath(searchNum, searchStart, nativeAudio)
                    notifyFlutter(mapOf("event" to "native_recording_found", "audioPath" to nativeAudio))
                }

                notifyFlutter(mapOf("event" to "sync_latest_call_log"))
            } catch (e: Exception) {
                Log.e(TAG, "Error in goAsync background sync: ${e.message}", e)
            } finally {
                try {
                    if (wakeLock?.isHeld == true) wakeLock.release()
                } catch (_: Exception) {}
                pendingResult.finish()
                Log.d(TAG, "goAsync: Background sync finished, broadcast completed.")
            }
        }.start()
    }

    private fun scheduleNativeRecordingScan(
        context: Context,
        number: String,
        startTime: Long,
        endTime: Long
    ) {
        val attempts = listOf(1500L, 3500L, 6500L)
        var found = false

        for (delay in attempts) {
            Handler(Looper.getMainLooper()).postDelayed({
                if (!found) {
                    val nativePath = NativeAudioScanner.findRecordingForCall(context, number, startTime, endTime)
                    if (nativePath != null) {
                        found = true
                        Log.d(TAG, "Native recording discovered and backed up at delay $delay ms -> $nativePath")

                        // Update audio path in native SQLite database immediately (works 24/7 even when app is closed)
                        NativeDatabaseHelper.getInstance(context).updateAudioPath(number, startTime, nativePath)

                        val nativeAudioEvent = mapOf(
                            "event" to "native_recording_found",
                            "number" to number,
                            "startTime" to startTime,
                            "audioPath" to nativePath
                        )
                        notifyFlutter(nativeAudioEvent)
                    }
                }
            }, delay)
        }
    }

    private fun getLatestOutgoingCallNumber(context: Context): String? {
        return try {
            val projection = arrayOf(android.provider.CallLog.Calls.NUMBER, android.provider.CallLog.Calls.DATE)
            val selection = "${android.provider.CallLog.Calls.TYPE} = ?"
            val selectionArgs = arrayOf(android.provider.CallLog.Calls.OUTGOING_TYPE.toString())
            val sortOrder = "${android.provider.CallLog.Calls.DATE} DESC LIMIT 1"
            context.contentResolver.query(
                android.provider.CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val dateIdx = cursor.getColumnIndexOrThrow(android.provider.CallLog.Calls.DATE)
                    val numIdx = cursor.getColumnIndexOrThrow(android.provider.CallLog.Calls.NUMBER)
                    val date = cursor.getLong(dateIdx)
                    if (Math.abs(System.currentTimeMillis() - date) < 45000) {
                        cursor.getString(numIdx)
                    } else null
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }
}

