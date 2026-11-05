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

                "playAudio" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val duration = playAudio(path)
                        result.success(duration)
                    } else {
                        result.error("INVALID_PATH", "Path is required", null)
                    }
                }

                "pauseAudio" -> {
                    pauseAudio()
                    result.success(true)
                }

                "resumeAudio" -> {
                    resumeAudio()
                    result.success(true)
                }

                "stopAudio" -> {
                    stopAudio()
                    result.success(true)
                }

                "seekAudio" -> {
                    val positionMs = call.argument<Int>("position") ?: 0
                    seekAudio(positionMs)
                    result.success(true)
                }

                "getAudioDuration" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        result.success(getAudioDuration(path))
                    } else {
                        result.success(0)
                    }
                }

                "findNativeRecordingForCall" -> {
                    val number = call.argument<String>("number") ?: ""
                    val startTime = (call.argument<Number>("startTime"))?.toLong() ?: 0L
                    val endTime = (call.argument<Number>("endTime"))?.toLong() ?: 0L
                    val path = NativeAudioScanner.findRecordingForCall(this, number, startTime, endTime)
                    result.success(path)
                }

                "scanAllNativeRecordings" -> {
                    val recordings = NativeAudioScanner.scanAllNativeRecordings()
                    result.success(recordings)
                }

                "copyAudioToAppStorage" -> {
                    val path = call.argument<String>("path") ?: ""
                    val number = call.argument<String>("number") ?: "call"
                    if (path.isNotEmpty()) {
                        val copied = NativeAudioScanner.backupToAppStorage(this, java.io.File(path), number)
                        result.success(copied)
                    } else {
                        result.success(null)
                    }
                }

                "checkAllFilesAccess" -> {
                    val hasAccess = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        android.os.Environment.isExternalStorageManager()
                    } else {
                        true
                    }
                    result.success(hasAccess)
                }

                "openAllFilesAccessSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }

                "syncHistoricalCalls" -> {
                    Thread {
                        val count = NativeDatabaseHelper(this).syncHistoricalCalls(200)
                        runOnUiThread {
                            result.success(count)
                        }
                    }.start()
                }

                "pickAudioWithSystemPicker" -> {
                    pendingPickerResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "application/ogg", "audio/x-wav", "audio/wav"))
                        }
                        startActivityForResult(intent, REQUEST_CODE_PICK_AUDIO)
                    } catch (e: Exception) {
                        pendingPickerResult = null
                        result.error("PICKER_ERROR", e.message, null)
                    }
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

        // Connect CallMonitorService notification callback to Flutter
        CallMonitorService.onCallLoggedListener = {
            runOnUiThread {
                methodChannel?.invokeMethod("onCallLogged", null)
            }
        }

        // Process any audio shared directly from phone dialer
        handleSendIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSendIntent(intent)
    }

    private fun handleSendIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type?.startsWith("audio/") == true) {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, android.net.Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
            } ?: intent.data

            if (uri != null) {
                try {
                    val appRecordingsDir = java.io.File(getExternalFilesDir(null), "recordings").apply {
                        if (!exists()) mkdirs()
                    }
                    val fileName = "dialer_shared_${System.currentTimeMillis()}.wav"
                    val destFile = java.io.File(appRecordingsDir, fileName)

                    contentResolver.openInputStream(uri)?.use { input ->
                        java.io.FileOutputStream(destFile).use { output ->
                            input.copyTo(output)
                        }
                    }

                    // Update native SQLite database immediately
                    NativeDatabaseHelper.getInstance(this).updateAudioPath("", System.currentTimeMillis(), destFile.absolutePath)

                    runOnUiThread {
                        methodChannel?.invokeMethod("onAudioSharedFromDialer", destFile.absolutePath)
                    }
                    Log.d("MainActivity", "Successfully saved shared audio from dialer: ${destFile.absolutePath}")
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error receiving shared audio from dialer: ${e.message}", e)
                }
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

    private var mediaPlayer: android.media.MediaPlayer? = null

    private fun playAudio(path: String): Int {
        stopAudio()
        return try {
            val player = android.media.MediaPlayer().apply {
                setDataSource(path)
                prepare()
                start()
                setOnCompletionListener {
                    runOnUiThread {
                        methodChannel?.invokeMethod("onAudioPlaybackCompleted", null)
                    }
                }
            }
            mediaPlayer = player
            player.duration
        } catch (e: Exception) {
            Log.e("MainActivity", "Error playing audio $path: ${e.message}", e)
            0
        }
    }

    private fun pauseAudio() {
        try {
            if (mediaPlayer?.isPlaying == true) {
                mediaPlayer?.pause()
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "Error pausing audio: ${e.message}")
        }
    }

    private fun resumeAudio() {
        try {
            mediaPlayer?.start()
        } catch (e: Exception) {
            Log.w("MainActivity", "Error resuming audio: ${e.message}")
        }
    }

    private fun stopAudio() {
        try {
            mediaPlayer?.apply {
                if (isPlaying) {
                    stop()
                }
                release()
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "Error stopping audio: ${e.message}")
        } finally {
            mediaPlayer = null
        }
    }

    private fun seekAudio(positionMs: Int) {
        try {
            mediaPlayer?.seekTo(positionMs)
        } catch (e: Exception) {
            Log.w("MainActivity", "Error seeking audio: ${e.message}")
        }
    }

    private fun getAudioDuration(path: String): Int {
        return try {
            val mmr = android.media.MediaMetadataRetriever()
            mmr.setDataSource(path)
            val durationStr = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
            mmr.release()
            durationStr?.toIntOrNull() ?: 0
        } catch (e: Exception) {
            0
        }
    }

    private val REQUEST_CODE_PICK_AUDIO = 2001
    private var pendingPickerResult: io.flutter.plugin.common.MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PICK_AUDIO) {
            val uri = data?.data
            if (resultCode == RESULT_OK && uri != null) {
                try {
                    val appRecordingsDir = java.io.File(getExternalFilesDir(null), "recordings").apply {
                        if (!exists()) mkdirs()
                    }
                    val fileName = "picked_${System.currentTimeMillis()}.wav"
                    val destFile = java.io.File(appRecordingsDir, fileName)

                    contentResolver.openInputStream(uri)?.use { input ->
                        java.io.FileOutputStream(destFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                    pendingPickerResult?.success(destFile.absolutePath)
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error copying picked audio: ${e.message}", e)
                    pendingPickerResult?.success(null)
                }
            } else {
                pendingPickerResult?.success(null)
            }
            pendingPickerResult = null
        }
    }

    override fun onDestroy() {
        stopAudio()
        CallStateReceiver.callEventListener = null
        super.onDestroy()
    }
}

