package com.example.call_logger

import android.content.Context
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import java.io.File

/**
 * CallAudioRecorder
 *
 * Automatically records voice call audio when an active call is connected (OFFHOOK).
 * Saves audio in MPEG-4 (.m4a) format inside the app's external files directory.
 */
object CallAudioRecorder {

    private const val TAG = "CallAudioRecorder"
    private var mediaRecorder: MediaRecorder? = null
    private var currentOutputFile: String? = null
    private var isRecording = false
    private var originalSpeakerphoneState: Boolean = false
    private var originalAudioMode: Int = AudioManager.MODE_NORMAL

    @Synchronized
    fun startRecording(context: Context, number: String): Boolean {
        if (isRecording) {
            Log.w(TAG, "Recording is already active")
            return false
        }

        try {
            // Check preference for auto-speakerphone to help mic capture both caller & receiver voices
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val useSpeakerphone = prefs.getBoolean("flutter.auto_speakerphone_recording", true)

            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null && useSpeakerphone) {
                originalSpeakerphoneState = audioManager.isSpeakerphoneOn
                originalAudioMode = audioManager.mode

                try {
                    audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                    audioManager.isSpeakerphoneOn = true
                    Log.d(TAG, "Speakerphone engaged for audio recording")
                } catch (e: Exception) {
                    Log.w(TAG, "Could not engage speakerphone: ${e.message}")
                }
            }

            // Prepare output folder: /Android/data/com.example.call_logger/files/recordings/
            val recordingsDir = File(context.getExternalFilesDir(null), "recordings").apply {
                if (!exists()) mkdirs()
            }

            val sanitizedNumber = number.replace(Regex("[^0-9+]"), "").ifEmpty { "unknown" }
            val timestamp = System.currentTimeMillis()
            val outputFile = File(recordingsDir, "call_${sanitizedNumber}_$timestamp.m4a")
            currentOutputFile = outputFile.absolutePath

            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            // Prefer VOICE_COMMUNICATION, fallback to MIC for universal device compatibility
            var sourceSet = false
            try {
                recorder.setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                sourceSet = true
            } catch (e: Exception) {
                Log.w(TAG, "VOICE_COMMUNICATION audio source failed, falling back to MIC: ${e.message}")
            }

            if (!sourceSet) {
                recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            }

            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(128000)
            recorder.setAudioSamplingRate(44100)
            recorder.setOutputFile(currentOutputFile)

            recorder.prepare()
            recorder.start()

            mediaRecorder = recorder
            isRecording = true
            Log.d(TAG, "Audio recording started successfully -> $currentOutputFile")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start call recording: ${e.message}", e)
            cleanup()
            return false
        }
    }

    @Synchronized
    fun stopRecording(context: Context? = null): String? {
        if (!isRecording) {
            return null
        }

        val recordedPath = currentOutputFile
        try {
            mediaRecorder?.apply {
                try {
                    stop()
                } catch (e: Exception) {
                    Log.w(TAG, "Error stopping recorder: ${e.message}")
                }
                release()
            }
            Log.d(TAG, "Recording stopped: $recordedPath")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing MediaRecorder: ${e.message}", e)
        } finally {
            cleanup()

            // Restore original audio state if speakerphone was engaged
            context?.let { ctx ->
                val audioManager = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager != null) {
                    try {
                        audioManager.isSpeakerphoneOn = originalSpeakerphoneState
                        audioManager.mode = originalAudioMode
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not restore audio manager state: ${e.message}")
                    }
                }
            }
        }

        // Verify that the output file exists and has content
        if (recordedPath != null) {
            val file = File(recordedPath)
            if (file.exists() && file.length() > 500) {
                return recordedPath
            } else {
                Log.w(TAG, "Recorded audio file was empty or too small, discarding")
            }
        }
        return null
    }

    private fun cleanup() {
        mediaRecorder = null
        currentOutputFile = null
        isRecording = false
    }
}

