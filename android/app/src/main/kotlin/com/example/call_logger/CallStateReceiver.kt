package com.example.call_logger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
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

        // Listener for Flutter MainActivity communication
        var callEventListener: ((Map<String, Any?>) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
            return
        }

        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        // Try extracting SIM slot information
        extractSimSlot(context, intent)

        Log.d(TAG, "PHONE_STATE broadcast: state=$stateStr, incomingNumber=$incomingNumber, slot=$detectedSimSlot")

        val state = when (stateStr) {
            TelephonyManager.EXTRA_STATE_RINGING -> TelephonyManager.CALL_STATE_RINGING
            TelephonyManager.EXTRA_STATE_OFFHOOK -> TelephonyManager.CALL_STATE_OFFHOOK
            TelephonyManager.EXTRA_STATE_IDLE -> TelephonyManager.CALL_STATE_IDLE
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
                // Start automatic voice call recording
                CallAudioRecorder.startRecording(context, savedNumber ?: "Unknown")

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

            TelephonyManager.CALL_STATE_IDLE -> {
                // Call ended -> Stop voice recording
                val audioPath = CallAudioRecorder.stopRecording(context)

                val endTime = System.currentTimeMillis()
                val durationSec = if (callStartTime > 0) ((endTime - callStartTime) / 1000).toInt() else 0

                val callType: String
                val callStatus: String

                if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                    // Ringing directly transitioned to IDLE -> Missed or rejected call
                    callType = "missed"
                    callStatus = "missed"
                } else if (isIncoming) {
                    callType = "incoming"
                    callStatus = "ended"
                } else {
                    callType = "outgoing"
                    callStatus = "ended"
                }

                val event = mutableMapOf<String, Any?>(
                    "event" to "ended",
                    "number" to (savedNumber ?: "Unknown"),
                    "callType" to callType,
                    "callStatus" to callStatus,
                    "startTime" to callStartTime,
                    "endTime" to endTime,
                    "durationSeconds" to durationSec,
                    "simSlot" to detectedSimSlot,
                    "audioPath" to audioPath
                )

                // Dispatch notification to Flutter. We also schedule a delayed call log query (1.5s)
                // because Android OS takes 1-2 seconds after IDLE to flush the finalized CallLog entry to disk.
                notifyFlutter(event)

                Handler(Looper.getMainLooper()).postDelayed({
                    val delayedSyncEvent = mapOf("event" to "sync_latest_call_log")
                    notifyFlutter(delayedSyncEvent)
                }, 1500)

                // Reset state
                isIncoming = false
                callStartTime = 0
                savedNumber = null
            }
        }

        lastState = state
    }

    private fun notifyFlutter(data: Map<String, Any?>) {
        Handler(Looper.getMainLooper()).post {
            callEventListener?.invoke(data)
        }
    }
}

