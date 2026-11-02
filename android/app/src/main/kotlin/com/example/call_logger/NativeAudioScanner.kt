package com.example.call_logger

import android.content.ContentUris
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File

/**
 * NativeAudioScanner
 *
 * Automatically detects and retrieves native phone call audio files recorded by the
 * phone's built-in dialer (such as Samsung's "Record calls" feature).
 *
 * Scans both the system MediaStore and standard OEM directories:
 * - /storage/emulated/0/Recordings/Call/ (Samsung default)
 * - /storage/emulated/0/Call/
 * - /storage/emulated/0/Music/Recordings/Call/
 * - /storage/emulated/0/Recordings/call_rec/ (Xiaomi / OnePlus / Oppo)
 */
object NativeAudioScanner {

    private const val TAG = "NativeAudioScanner"

    private val STANDARD_DIRS = listOf(
        "/storage/emulated/0/Recordings/Call",
        "/storage/emulated/0/Call",
        "/storage/emulated/0/Music/Recordings/Call",
        "/storage/emulated/0/Recordings/call_rec",
        "${Environment.getExternalStorageDirectory().absolutePath}/Recordings/Call",
        "${Environment.getExternalStorageDirectory().absolutePath}/Call",
        "${Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC).absolutePath}/Recordings/Call"
    )

    /**
     * Searches for a native call recording file matching the given call number and timestamp window.
     */
    fun findRecordingForCall(
        context: Context,
        number: String,
        callStartTimeMs: Long,
        callEndTimeMs: Long
    ): String? {
        val sanitizedNumber = number.replace(Regex("[^0-9]"), "")

        // 1. Direct scan of standard physical directories
        val directMatch = scanDirectoriesForCall(sanitizedNumber, callStartTimeMs, callEndTimeMs)
        if (directMatch != null) {
            Log.d(TAG, "Found native recording via directory scan: $directMatch")
            return backupToAppStorage(context, directMatch, sanitizedNumber)
        }

        // 2. Scan via MediaStore Audio provider
        val mediaStoreMatch = scanMediaStoreForCall(context, sanitizedNumber, callStartTimeMs, callEndTimeMs)
        if (mediaStoreMatch != null) {
            Log.d(TAG, "Found native recording via MediaStore: $mediaStoreMatch")
            return backupToAppStorage(context, mediaStoreMatch, sanitizedNumber)
        }

        return null
    }

    /**
     * Copies the native recording file into our app's private external files directory
     * (/Android/data/com.example.call_logger/files/recordings/).
     * This creates a safe backup copy so that even if the user manually deletes the original
     * recording in Samsung's /Recordings/Call/ directory, our app keeps the audio file preserved!
     */
    fun backupToAppStorage(context: Context, sourcePath: String, number: String): String {
        return try {
            val sourceFile = File(sourcePath)
            if (!sourceFile.exists() || sourceFile.length() < 100) {
                return sourcePath
            }

            val appRecordingsDir = File(context.getExternalFilesDir(null), "recordings").apply {
                if (!exists()) mkdirs()
            }

            val safeNumber = number.replace(Regex("[^0-9+]"), "").ifEmpty { "unknown" }
            val backupFileName = "backup_${safeNumber}_${sourceFile.name}"
            val destFile = File(appRecordingsDir, backupFileName)

            // If already backed up with matching size, return destination path
            if (destFile.exists() && destFile.length() == sourceFile.length()) {
                Log.d(TAG, "Audio already backed up in app storage: ${destFile.absolutePath}")
                return destFile.absolutePath
            }

            sourceFile.copyTo(destFile, overwrite = true)
            Log.d(TAG, "Successfully created independent backup in app storage: ${destFile.absolutePath}")
            destFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy recording to app backup storage: ${e.message}", e)
            sourcePath // Fallback to original path if copy fails
        }
    }

    private fun scanDirectoriesForCall(
        sanitizedNumber: String,
        callStartTimeMs: Long,
        callEndTimeMs: Long
    ): String? {
        val candidateFiles = mutableListOf<File>()

        for (dirPath in STANDARD_DIRS) {
            val dir = File(dirPath)
            if (dir.exists() && dir.isDirectory) {
                val files = dir.listFiles { f ->
                    f.isFile && (f.extension.equals("m4a", true) ||
                            f.extension.equals("mp3", true) ||
                            f.extension.equals("amr", true) ||
                            f.extension.equals("aac", true))
                } ?: continue

                candidateFiles.addAll(files)
            }
        }

        if (candidateFiles.isEmpty()) return null

        // Sort newest first
        candidateFiles.sortByDescending { it.lastModified() }

        // Step A: Look for file containing the phone number
        if (sanitizedNumber.length >= 4) {
            val last4 = sanitizedNumber.takeLast(4)
            val matchedByNumber = candidateFiles.firstOrNull { file ->
                val name = file.nameWithoutExtension.replace(Regex("[^0-9]"), "")
                name.contains(sanitizedNumber) || (last4.isNotEmpty() && name.contains(last4))
            }
            if (matchedByNumber != null) {
                return matchedByNumber.absolutePath
            }
        }

        // Step B: Look for file created/modified within 2 minutes of the call end time
        val referenceTime = if (callEndTimeMs > 0) callEndTimeMs else System.currentTimeMillis()
        val timeWindowMs = 2 * 60 * 1000 // 2 minutes

        val matchedByTime = candidateFiles.firstOrNull { file ->
            val diff = Math.abs(file.lastModified() - referenceTime)
            diff <= timeWindowMs
        }

        return matchedByTime?.absolutePath
    }

    private fun scanMediaStoreForCall(
        context: Context,
        sanitizedNumber: String,
        callStartTimeMs: Long,
        callEndTimeMs: Long
    ): String? {
        return try {
            val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_MODIFIED
            )

            // Look for files modified around call time
            val refSec = (if (callEndTimeMs > 0) callEndTimeMs else System.currentTimeMillis()) / 1000
            val minSec = refSec - (5 * 60) // 5 min window
            val maxSec = refSec + (5 * 60)

            val selection = "${MediaStore.Audio.Media.DATE_MODIFIED} >= ? AND ${MediaStore.Audio.Media.DATE_MODIFIED} <= ?"
            val selectionArgs = arrayOf(minSec.toString(), maxSec.toString())
            val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"

            context.contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)

                while (cursor.moveToNext()) {
                    val filePath = cursor.getString(dataIndex) ?: continue
                    val fileName = cursor.getString(nameIndex) ?: ""

                    // Check if path is in call recordings
                    val isCallDir = filePath.contains("Call", ignoreCase = true) ||
                            filePath.contains("Recordings", ignoreCase = true) ||
                            filePath.contains("call_rec", ignoreCase = true)

                    if (isCallDir) {
                        if (sanitizedNumber.length >= 4 && fileName.contains(sanitizedNumber.takeLast(4))) {
                            return filePath
                        }
                        return filePath
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
     * Scans and returns all available native call recording files found on the device.
     */
    fun scanAllNativeRecordings(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val candidateFiles = mutableListOf<File>()

        for (dirPath in STANDARD_DIRS) {
            val dir = File(dirPath)
            if (dir.exists() && dir.isDirectory) {
                val files = dir.listFiles { f ->
                    f.isFile && (f.extension.equals("m4a", true) ||
                            f.extension.equals("mp3", true) ||
                            f.extension.equals("amr", true) ||
                            f.extension.equals("aac", true))
                } ?: continue

                candidateFiles.addAll(files)
            }
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

