package com.example.call_logger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager

/**
 * CallStateReceiver
 *
 * Lightweight broadcast receiver for Call Log Keeper to forward call events
 * into Flutter via MainActivity method channel if needed.
 */
class CallStateReceiver : BroadcastReceiver() {

    companion object {
        var callEventListener: ((Map<String, Any?>) -> Unit)? = null

        fun notifyFlutter(data: Map<String, Any?>) {
            Handler(Looper.getMainLooper()).post {
                callEventListener?.invoke(data)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        val event = mapOf(
            "event" to when (stateStr) {
                TelephonyManager.EXTRA_STATE_RINGING -> "ringing"
                TelephonyManager.EXTRA_STATE_OFFHOOK -> "connected"
                TelephonyManager.EXTRA_STATE_IDLE -> "ended"
                else -> "idle"
            },
            "number" to (incomingNumber ?: "Unknown")
        )
        notifyFlutter(event)
    }
}
