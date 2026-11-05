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
 * Scans, finds, and automatically copies call recordings (.wav, .m4a, .mp3, .aac, .amr)
 * from Vivo, Realme, Oppo, Samsung, and other Android OEM dialers into the app's protected storage.
 */
object NativeAudioScanner {

    private const val TAG = "NativeAudioScanner"

    // Primary directories across Vivo, Realme, Samsung, Xiaomi & Oppo
    private val BASE_SEARCH_DIRS by lazy {
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
            // Vivo & iQOO (.wav is very common here)
            "$extStorage/Record/Call",
            "$extStorage/Record",
            "$extStorage/Recordings/Call",
            "$extStorage/Sounds/Call",
            "$extStorage/Sounds",
            "$extStorage/vivo/Record/Call",
            "$extStorage/vivo/Record",
            "$extStorage/vivo",
            "$extStorage/Recorder",
            "$extStorage/VoiceRecorder",
            "$extStorage/voice_recorder",

            // Realme & Oppo (.wav / .mp3 / .m4a / .aac)
            "$musicDir/Recordings/Call Recordings",
            "$recDir/Call Recordings",
            "$extStorage/Recordings/Call Recordings",
            "$extStorage/Music/Recordings/Call Recordings",
            "$musicDir/Recordings",
            "$extStorage/Recordings/Call",
            "$extStorage/ColorOS/Recordings/Call",
            "$extStorage/ColorOS/Recordings",
            "$extStorage/ColorOS",

            // Samsung One UI
            "$extStorage/Recordings/Call",
            "$extStorage/Call",
            "$musicDir/Recordings/Call",

            // Xiaomi / Redmi MIUI
            "$extStorage/MIUI/sound_recorder/call_rec",
            "$extStorage/Recordings/call_rec",

            // Common / System standard paths
            "$recDir/Call",
            recDir,
            "$musicDir/Call",
            musicDir,
            "$extStorage/Call",
            "$extStorage/Audio",
            "$extStorage/Download"
        ).distinct()
    }

    /**
     * Recursively collects all audio files (.wav, .m4a, .mp3, .aac, .amr) up to maxDepth.
     */
    private fun collectAudioFiles(dir: File, list: MutableList<File>, depth: Int = 0) {
        if (depth > 3 || !dir.exists() || !dir.isDirectory) return
        try {
            val files = dir.listFiles() ?: return
            for (f in files) {
                if (f.isFile && isAudioFile(f)) {
                    list.add(f)
                } else if (f.isDirectory && !f.name.startsWith(".")) {
                    collectAudioFiles(f, list, depth + 1)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error listing files in ${dir.absolutePath}: ${e.message}")
        }
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

        // 1. Direct recursive scan of all OEM directories (prioritizing .wav, .m4a, .mp3)
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

    /**
     * Scans for a native call recording, copies it into our app's storage location,
     * updates the SQLite database with the new copied path, and returns the path.
     */
    fun scanAndAttachRecording(
        context: Context,
        number: String?,
        callStartTimeMs: Long,
        callEndTimeMs: Long
    ): String? {
        try {
            val safeNumber = number ?: ""
            Log.d(TAG, "scanAndAttachRecording for number=$safeNumber, start=$callStartTimeMs, end=$callEndTimeMs")
            val copiedPath = findRecordingForCall(context, safeNumber, callStartTimeMs, callEndTimeMs)
            if (!copiedPath.isNullOrBlank()) {
                val refDate = if (callStartTimeMs > 0) callStartTimeMs else callEndTimeMs
                val updated = NativeDatabaseHelper.getInstance(context).updateAudioPath(safeNumber, refDate, copiedPath)
                Log.d(TAG, "Attached recording to call record (rows updated: $updated): $copiedPath")
                return copiedPath
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in scanAndAttachRecording: ${e.message}", e)
        }
        return null
    }

    private fun scanDirectoriesForCall(
        sanitizedNumber: String,
        callStartTimeMs: Long,
        callEndTimeMs: Long
    ): File? {
        val candidateFiles = mutableListOf<File>()

        for (dirPath in BASE_SEARCH_DIRS) {
            val dir = File(dirPath)
            if (dir.exists() && dir.isDirectory) {
                collectAudioFiles(dir, candidateFiles, 0)
            }
        }

        if (candidateFiles.isEmpty()) return null

        // Deduplicate and sort newest first
        val distinctFiles = candidateFiles.distinctBy { it.absolutePath }.sortedByDescending { it.lastModified() }

        // Match 1: By phone number in filename (supports .wav, .mp3, .m4a, etc.)
        if (sanitizedNumber.length >= 4) {
            val last4 = sanitizedNumber.takeLast(4)
            val last7 = if (sanitizedNumber.length >= 7) sanitizedNumber.takeLast(7) else last4
            val matchedByNumber = distinctFiles.firstOrNull { file ->
                val digits = file.nameWithoutExtension.replace(Regex("[^0-9]"), "")
                digits.contains(sanitizedNumber) || digits.contains(last7) || (last4.isNotEmpty() && digits.contains(last4))
            }
            if (matchedByNumber != null) {
                Log.d(TAG, "Matched file by phone number: ${matchedByNumber.name}")
                return matchedByNumber
            }
        }

        // Match 2: Timestamp matching for calls (whether just ended or from call history)
        if (callStartTimeMs > 0 || callEndTimeMs > 0) {
            val startRef = if (callStartTimeMs > 0) callStartTimeMs - (90 * 1000) else (callEndTimeMs - 180 * 1000)
            val endRef = (if (callEndTimeMs > 0) callEndTimeMs else callStartTimeMs) + (180 * 1000)

            val matchedByTime = distinctFiles.firstOrNull { file ->
                val mod = file.lastModified()
                mod in startRef..endRef
            }

            if (matchedByTime != null) {
                Log.d(TAG, "Matched file by call time window: ${matchedByTime.name}")
                return matchedByTime
            }
        }

        // Match 3: If call literally just ended (within last 3 minutes), pick the newest recording file
        val newest = distinctFiles.first()
        if (Math.abs(System.currentTimeMillis() - newest.lastModified()) < 180 * 1000) {
            Log.d(TAG, "Matched newest recently created file: ${newest.name}")
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

            val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"

            context.contentResolver.query(uri, projection, null, null, sortOrder)?.use { cursor ->
                val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val modIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)

                val last4 = if (sanitizedNumber.length >= 4) sanitizedNumber.takeLast(4) else ""

                while (cursor.moveToNext()) {
                    val filePath = cursor.getString(dataIndex) ?: continue
                    val fileName = cursor.getString(nameIndex) ?: ""
                    val modSec = cursor.getLong(modIndex)
                    val modMs = modSec * 1000

                    val file = File(filePath)
                    if (!file.exists() || file.length() < 100) continue
                    if (!isAudioFile(file)) continue

                    val isCallDir = filePath.contains("Call", ignoreCase = true) ||
                            filePath.contains("Record", ignoreCase = true) ||
                            filePath.contains("voice", ignoreCase = true) ||
                            filePath.contains("sound", ignoreCase = true)

                    if (isCallDir) {
                        // Check phone number match
                        if (last4.isNotEmpty() && fileName.contains(last4)) {
                            return file
                        }

                        // Check time window match
                        if (callStartTimeMs > 0 || callEndTimeMs > 0) {
                            val startRef = if (callStartTimeMs > 0) callStartTimeMs - (90 * 1000) else (callEndTimeMs - 180 * 1000)
                            val endRef = (if (callEndTimeMs > 0) callEndTimeMs else callStartTimeMs) + (180 * 1000)
                            if (modMs in startRef..endRef) {
                                return file
                            }
                        }
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

            val safeNumber = number.replace(Regex("[^0-9+]"), "").ifEmpty { "call" }
            val extension = sourceFile.extension.ifEmpty { "wav" }
            val backupFileName = "backup_${safeNumber}_${System.currentTimeMillis()}.$extension"
            val destFile = File(appRecordingsDir, backupFileName)

            sourceFile.copyTo(destFile, overwrite = true)
            Log.d(TAG, "Successfully copied and backed up: ${destFile.absolutePath}")
            destFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy recording: ${e.message}", e)
            sourceFile.absolutePath
        }
    }

    /**
     * Supports .wav, .m4a, .mp3, .amr, .aac, .ogg, .3gp
     */
    fun isAudioFile(file: File): Boolean {
        val ext = file.extension.lowercase()
        return ext == "wav" || ext == "m4a" || ext == "mp3" || ext == "amr" || ext == "aac" || ext == "ogg" || ext == "3gp"
    }

    /**
     * Scans and returns all available audio files across all device recording directories.
     */
    fun scanAllNativeRecordings(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val candidateFiles = mutableListOf<File>()

        for (dirPath in BASE_SEARCH_DIRS) {
            val dir = File(dirPath)
            if (dir.exists() && dir.isDirectory) {
                collectAudioFiles(dir, candidateFiles, 0)
            }
        }

        val distinctFiles = candidateFiles.distinctBy { it.absolutePath }.sortedByDescending { it.lastModified() }

        for (file in distinctFiles) {
            result.add(
                mapOf(
                    "path" to file.absolutePath,
                    "name" to file.name,
                    "extension" to file.extension.lowercase(),
                    "size" to file.length(),
                    "lastModified" to file.lastModified()
                )
            )
        }

        return result
    }
}
