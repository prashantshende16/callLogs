package com.example.call_logger

import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File

/**
 * NativeAudioScanner
 *
 * Scans, finds, and automatically copies call recordings from native dialers
 * (Vivo, Realme, Oppo, Samsung, Xiaomi, OnePlus) into the app's protected storage.
 */
object NativeAudioScanner {

    private const val TAG = "NativeAudioScanner"

    // Comprehensive list of standard recording paths across Vivo, Realme, Samsung, Xiaomi & Oppo
    private val STANDARD_DIRS by lazy {
        val extStorage = Environment.getExternalStorageDirectory().absolutePath
        val musicDir = try { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC).absolutePath } catch (_: Exception) { "$extStorage/Music" }
        val recDir = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_RECORDINGS).absolutePath
            } else {
                "$extStorage/Recordings"
            }
        } catch (_: Exception) { "$extStorage/Recordings" }

        listOf(
            // Vivo / iQOO paths
            "$extStorage/Record/Call",
            "$extStorage/Record",
            "$extStorage/Recordings/Call",
            "$extStorage/Sounds/Call",
            "$extStorage/vivo/Record/Call",
            "$extStorage/vivo/Record",

            // Realme / Oppo (Realme UI / ColorOS) paths
            "$musicDir/Recordings/Call Recordings",
            "$recDir/Call Recordings",
            "$extStorage/Recordings/Call Recordings",
            "$extStorage/Music/Recordings/Call Recordings",
            "$musicDir/Recordings",
            "$extStorage/Recordings/Call",
            "$extStorage/ColorOS/Recordings/Call",

            // Samsung One UI paths
            "$extStorage/Recordings/Call",
            "$extStorage/Call",
            "$musicDir/Recordings/Call",

            // Xiaomi / Redmi / POCO MIUI paths
            "$extStorage/MIUI/sound_recorder/call_rec",
            "$extStorage/Recordings/call_rec",

            // Generic / AOSP paths
            "$recDir/Call",
            recDir,
            "$musicDir/Call"
        ).distinct()
    }

    /**
     * Finds a native call recording, copies it into our app's storage location, and returns the copy's path.
     */
    fun findRecordingForCall(
        context: Context,
        number: String,
        callStartTimeMs: Long,
        callEndTimeMs: Long
    ): String? {
        val sanitizedNumber = number.replace(Regex("[^0-9]"), "")

        // 1. Direct scan of all OEM directories
        val directMatch = scanDirectoriesForCall(sanitizedNumber, callStartTimeMs, callEndTimeMs)
        if (directMatch != null) {
            Log.d(TAG, "Found native recording via directory scan: ${directMatch.absolutePath}")
            return backupToAppStorage(context, directMatch, sanitizedNumber)
        }

        // 2. Scan via MediaStore Audio provider
        val mediaStoreMatch = scanMediaStoreForCall(context, sanitizedNumber, callStartTimeMs, callEndTimeMs)
        if (mediaStoreMatch != null) {
            Log.d(TAG, "Found native recording via MediaStore: ${mediaStoreMatch.absolutePath}")
            return backupToAppStorage(context, mediaStoreMatch, sanitizedNumber)
        }

        return null
    }

    private fun scanDirectoriesForCall(
        sanitizedNumber: String,
        callStartTimeMs: Long,
        callEndTimeMs: Long
    ): File? {
        val candidateFiles = mutableListOf<File>()

        for (dirPath in STANDARD_DIRS) {
            try {
                val dir = File(dirPath)
                if (dir.exists() && dir.isDirectory) {
                    val files = dir.listFiles { f ->
                        f.isFile && isAudioFile(f)
                    } ?: continue

                    candidateFiles.addAll(files)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not read directory $dirPath: ${e.message}")
            }
        }

        if (candidateFiles.isEmpty()) return null

        // Sort newest first
        candidateFiles.sortByDescending { it.lastModified() }

        // Match 1: By phone number in filename
        if (sanitizedNumber.length >= 4) {
            val last4 = sanitizedNumber.takeLast(4)
            val matchedByNumber = candidateFiles.firstOrNull { file ->
                val digits = file.nameWithoutExtension.replace(Regex("[^0-9]"), "")
                digits.contains(sanitizedNumber) || (last4.isNotEmpty() && digits.contains(last4))
            }
            if (matchedByNumber != null) {
                return matchedByNumber
            }
        }

        // Match 2: Modified within 45 seconds of call end time (or current time if call just ended)
        val referenceTime = if (callEndTimeMs > 0) callEndTimeMs else System.currentTimeMillis()
        val timeWindowMs = 60 * 1000 // 60 seconds

        val matchedByTime = candidateFiles.firstOrNull { file ->
            val diff = Math.abs(file.lastModified() - referenceTime)
            diff <= timeWindowMs
        }

        if (matchedByTime != null) {
            return matchedByTime
        }

        // Match 3: The newest audio file in any call recording directory modified in the last 2 minutes
        val newest = candidateFiles.first()
        if (Math.abs(System.currentTimeMillis() - newest.lastModified()) < 120 * 1000) {
            return newest
        }

        return null
    }

    private fun scanMediaStoreForCall(
        context: Context,
        sanitizedNumber: String,
        callStartTimeMs: Long,
        callEndTimeMs: Long
    ): File? {
        return try {
            val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_MODIFIED
            )

            val refSec = (if (callEndTimeMs > 0) callEndTimeMs else System.currentTimeMillis()) / 1000
            val minSec = refSec - (3 * 60)
            val maxSec = refSec + (3 * 60)

            val selection = "${MediaStore.Audio.Media.DATE_MODIFIED} >= ? AND ${MediaStore.Audio.Media.DATE_MODIFIED} <= ?"
            val selectionArgs = arrayOf(minSec.toString(), maxSec.toString())
            val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"

            context.contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)

                while (cursor.moveToNext()) {
                    val filePath = cursor.getString(dataIndex) ?: continue
                    val fileName = cursor.getString(nameIndex) ?: ""
                    val file = File(filePath)

                    if (!file.exists() || file.length() < 100) continue

                    // Check if path is in a call recording directory
                    val isCallDir = filePath.contains("Call", ignoreCase = true) ||
                            filePath.contains("Record", ignoreCase = true) ||
                            filePath.contains("call_rec", ignoreCase = true)

                    if (isCallDir) {
                        if (sanitizedNumber.length >= 4 && fileName.contains(sanitizedNumber.takeLast(4))) {
                            return file
                        }
                        return file
                    }
                }
            }
            null
        } catch (e: Exception) {
            Log.w(TAG, "Error querying MediaStore: ${e.message}")
            null
        }
    }

    /**
     * Copies the native recording file into our app's private files directory:
     * /Android/data/com.example.call_logger/files/recordings/
     */
    fun backupToAppStorage(context: Context, sourceFile: File, number: String): String {
        return try {
            if (!sourceFile.exists() || sourceFile.length() < 100) {
                return sourceFile.absolutePath
            }

            val appRecordingsDir = File(context.getExternalFilesDir(null), "recordings").apply {
                if (!exists()) mkdirs()
            }

            val safeNumber = number.replace(Regex("[^0-9+]"), "").ifEmpty { "unknown" }
            val extension = sourceFile.extension.ifEmpty { "m4a" }
            val backupFileName = "backup_${safeNumber}_${System.currentTimeMillis()}.$extension"
            val destFile = File(appRecordingsDir, backupFileName)

            sourceFile.copyTo(destFile, overwrite = true)
            Log.d(TAG, "Backed up recording from ${sourceFile.absolutePath} to ${destFile.absolutePath}")
            destFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy recording: ${e.message}", e)
            sourceFile.absolutePath
        }
    }

    private fun isAudioFile(file: File): Boolean {
        val ext = file.extension.lowercase()
        return ext == "m4a" || ext == "mp3" || ext == "amr" || ext == "aac" || ext == "wav" || ext == "ogg" || ext == "3gp"
    }

    /**
     * Scans and returns all available native call recording files found across all paths.
     */
    fun scanAllNativeRecordings(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val candidateFiles = mutableListOf<File>()

        for (dirPath in STANDARD_DIRS) {
            try {
                val dir = File(dirPath)
                if (dir.exists() && dir.isDirectory) {
                    val files = dir.listFiles { f -> f.isFile && isAudioFile(f) } ?: continue
                    candidateFiles.addAll(files)
                }
            } catch (_: Exception) {}
        }

        candidateFiles.sortByDescending { it.lastModified() }

        for (file in candidateFiles) {
            result.add(
                mapOf(
                    "path" to file.absolutePath,
                    "name" to file.name,
                    "size" to file.length(),
                    "lastModified" to file.lastModified()
                )
            )
        }

        return result
    }
}
