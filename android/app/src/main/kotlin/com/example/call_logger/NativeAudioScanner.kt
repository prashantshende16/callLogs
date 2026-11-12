package com.example.call_logger

import android.content.ContentUris
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File

/**
 * NativeAudioScanner
 *
 * Scans, detects, and automatically copies native OEM phone call recordings
 * (.m4a, .wav, .mp3, .aac, .amr) across Realme (ColorOS / Realme UI), Samsung (One UI),
 * Vivo / iQOO, Xiaomi (MIUI / HyperOS), and Oppo into the app's protected storage.
 *
 * Supports both:
 * 1. ContentResolver / MediaStore (bypasses Scoped Storage even without All Files Access)
 * 2. Direct directory scanning (when All Files Access / MANAGE_EXTERNAL_STORAGE is granted)
 */
object NativeAudioScanner {

    private const val TAG = "NativeAudioScanner"

    // Search directories across Realme, Oppo, Samsung, Vivo, Xiaomi & Android standard paths
    val BASE_SEARCH_DIRS by lazy {
        val extStorage = Environment.getExternalStorageDirectory().absolutePath
        val musicDir = try {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC).absolutePath
        } catch (_: Exception) {
            "$extStorage/Music"
        }
        val recDir = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_RECORDINGS).absolutePath
            } else {
                "$extStorage/Recordings"
            }
        } catch (_: Exception) {
            "$extStorage/Recordings"
        }
        val soundsDir = "$extStorage/Sounds"

        listOf(
            // Realme & Oppo (Realme UI / ColorOS on RMX5051)
            "$recDir/Call Recordings",
            "$recDir/Call",
            "$musicDir/Recordings/Call Recordings",
            "$musicDir/Recordings/Call",
            "$extStorage/Recordings/Call Recordings",
            "$extStorage/Recordings/Call",
            "$extStorage/Music/Recordings/Call Recordings",
            "$extStorage/Music/Recordings/Call",
            "$extStorage/ColorOS/Recordings/Call",
            "$extStorage/ColorOS/Recordings",
            "$extStorage/ColorOS",
            "$musicDir/Recordings",
            recDir,
            "$extStorage/Recordings",

            // Samsung One UI (SM M045F)
            "$extStorage/Recordings/Call",
            "$extStorage/Call",
            "$musicDir/Recordings/Call",
            "$musicDir/Call",

            // Vivo / iQOO / FuntouchOS
            "$extStorage/Record/Call",
            "$extStorage/Record",
            "$extStorage/vivo/Record/Call",
            "$extStorage/vivo/Record",
            "$extStorage/vivo",
            "$extStorage/Recorder",
            "$extStorage/VoiceRecorder",
            "$extStorage/voice_recorder",

            // Xiaomi / Redmi MIUI / HyperOS
            "$extStorage/MIUI/sound_recorder/call_rec",
            "$extStorage/Recordings/call_rec",

            // General & Common paths
            "$soundsDir/Call",
            soundsDir,
            "$extStorage/Audio",
            "$extStorage/Download",
            musicDir,
            extStorage
        ).distinct()
    }

    /**
     * Triggers Android MediaScanner on recording folders so new recordings are indexed immediately.
     */
    fun triggerMediaScan(context: Context) {
        try {
            val existingDirs = BASE_SEARCH_DIRS.filter { File(it).exists() }.toTypedArray()
            if (existingDirs.isNotEmpty()) {
                MediaScannerConnection.scanFile(context, existingDirs, null) { path, uri ->
                    Log.d(TAG, "MediaScanner indexed: $path -> $uri")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "triggerMediaScan warning: ${e.message}")
        }
    }

    /**
     * Generates phone number digit substrings to match filenames regardless of country code prefix.
     */
    private fun getNumberVariants(number: String): List<String> {
        val digits = number.replace(Regex("[^0-9]"), "")
        if (digits.length < 3) return emptyList()
        val variants = mutableListOf<String>()
        variants.add(digits)
        if (digits.length >= 10) variants.add(digits.takeLast(10))
        if (digits.length >= 7) variants.add(digits.takeLast(7))
        if (digits.length >= 4) variants.add(digits.takeLast(4))
        return variants.distinct()
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
        Log.d(TAG, "Searching recording for number=$number, start=$callStartTimeMs, end=$callEndTimeMs")

        // 1. Direct recursive scan of all OEM directories (if accessible via All Files Access)
        val directMatch = scanDirectoriesForCall(context, number, callStartTimeMs, callEndTimeMs)
        if (directMatch != null) {
            Log.d(TAG, "Found recording via directory scan: ${directMatch.absolutePath}")
            return backupFileToAppStorage(context, directMatch, number)
        }

        // 2. Scan via MediaStore Audio provider (bypasses Scoped Storage using ContentResolver)
        val mediaStoreMatch = scanMediaStoreForCall(context, number, callStartTimeMs, callEndTimeMs)
        if (mediaStoreMatch != null) {
            Log.d(TAG, "Found and copied recording via MediaStore: $mediaStoreMatch")
            return mediaStoreMatch
        }

        // 3. Fallback: Check if there's any newly created recording file in the last 3 minutes
        val newestMatch = findNewestCallRecording(context)
        if (newestMatch != null) {
            Log.d(TAG, "Found newest recording via fallback: $newestMatch")
            return newestMatch
        }

        Log.w(TAG, "No recording found for call with number=$number")
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
            triggerMediaScan(context)
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

    /**
     * Scans and automatically links recordings to recent unattached calls in the local database.
     */
    fun attachRecordingsToUnattachedCalls(context: Context): Int {
        var count = 0
        try {
            triggerMediaScan(context)
            val helper = NativeDatabaseHelper.getInstance(context)
            val unattached = helper.getUnattachedCalls(20)
            for (call in unattached) {
                val number = call["number"] as? String ?: continue
                val date = (call["date"] as? Long) ?: 0L
                val dur = (call["duration"] as? Long) ?: 0L
                val endDate = date + (dur * 1000L)

                val audioPath = findRecordingForCall(context, number, date, endDate)
                if (audioPath != null) {
                    val updated = helper.updateAudioPath(number, date, audioPath)
                    if (updated > 0) count++
                }
            }
            if (count > 0) {
                Log.d(TAG, "attachRecordingsToUnattachedCalls: Successfully linked $count calls with audio recordings")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error attaching recordings to unattached calls: ${e.message}")
        }
        return count
    }

    /**
     * Direct filesystem scan (works when MANAGE_EXTERNAL_STORAGE is granted or on Android <= 10).
     */
    private fun scanDirectoriesForCall(
        context: Context,
        number: String,
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

        val appDir = File(context.getExternalFilesDir(null), "recordings").absolutePath
        val distinctFiles = candidateFiles
            .distinctBy { it.absolutePath }
            .filter { !it.absolutePath.startsWith(appDir) }
            .sortedByDescending { it.lastModified() }

        val variants = getNumberVariants(number)

        // 1. Phone number match AND time window match (highest confidence)
        if (variants.isNotEmpty() && (callStartTimeMs > 0 || callEndTimeMs > 0)) {
            val refStart = if (callStartTimeMs > 0) callStartTimeMs - (600 * 1000L) else (callEndTimeMs - 600 * 1000L)
            val refEnd = (if (callEndTimeMs > 0) callEndTimeMs else callStartTimeMs) + (600 * 1000L)
            for (file in distinctFiles) {
                val fileDigits = file.nameWithoutExtension.replace(Regex("[^0-9]"), "")
                for (variant in variants) {
                    if ((fileDigits.contains(variant) || file.name.contains(variant)) && file.lastModified() in refStart..refEnd) {
                        Log.d(TAG, "Direct scan matched by number variant ($variant) AND time window: ${file.name}")
                        return file
                    }
                }
            }
        }

        // 2. Phone number match regardless of time
        if (variants.isNotEmpty()) {
            for (file in distinctFiles) {
                val fileDigits = file.nameWithoutExtension.replace(Regex("[^0-9]"), "")
                for (variant in variants) {
                    if (fileDigits.contains(variant) || file.name.contains(variant)) {
                        Log.d(TAG, "Direct scan matched by number variant ($variant): ${file.name}")
                        return file
                    }
                }
            }
        }

        // 3. Any audio file in a call-recording specific folder created during/right after the call
        if (callStartTimeMs > 0 || callEndTimeMs > 0) {
            val refStart = if (callStartTimeMs > 0) callStartTimeMs - (120 * 1000L) else (callEndTimeMs - 180 * 1000L)
            val refEnd = (if (callEndTimeMs > 0) callEndTimeMs else callStartTimeMs) + (240 * 1000L)

            val matchedByTime = distinctFiles.firstOrNull { file ->
                val isCallFolderOrName = file.absolutePath.contains("call", true) ||
                        file.absolutePath.contains("record", true) ||
                        file.name.contains("call", true) ||
                        file.name.contains("record", true)
                isCallFolderOrName && file.lastModified() in refStart..refEnd
            }
            if (matchedByTime != null) {
                Log.d(TAG, "Direct scan matched by call directory & time window: ${matchedByTime.name}")
                return matchedByTime
            }
        }

        return null
    }

    /**
     * Queries MediaStore.Audio.Media and copies via ContentResolver.openInputStream.
     * This works reliably on Android 11, 12, 13, and 14 without needing All Files Access!
     */
    private fun scanMediaStoreForCall(
        context: Context,
        number: String,
        callStartTimeMs: Long,
        callEndTimeMs: Long
    ): String? {
        return try {
            val variants = getNumberVariants(number)
            val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val projection = mutableListOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.SIZE
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                projection.add(MediaStore.Audio.Media.RELATIVE_PATH)
            }
            try {
                projection.add(MediaStore.Audio.Media.DATA)
            } catch (_: Exception) {}

            val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC LIMIT 50"

            context.contentResolver.query(uri, projection.toTypedArray(), null, null, sortOrder)?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val nameIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                val modIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)
                val sizeIdx = cursor.getColumnIndex(MediaStore.Audio.Media.SIZE)
                val dataIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
                val relIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)
                } else -1

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idIdx)
                    val name = if (nameIdx >= 0) cursor.getString(nameIdx) ?: "" else ""
                    val modSec = if (modIdx >= 0) cursor.getLong(modIdx) else 0L
                    val modMs = modSec * 1000L
                    val size = if (sizeIdx >= 0) cursor.getLong(sizeIdx) else 0L
                    val data = if (dataIdx >= 0) cursor.getString(dataIdx) ?: "" else ""
                    val rel = if (relIdx >= 0) cursor.getString(relIdx) ?: "" else ""

                    if (size < 100 && size != 0L) continue
                    if (!isAudioFileName(name) && !isAudioFileName(data)) continue

                    val isCallRelated = name.contains("call", true) ||
                            name.contains("record", true) ||
                            data.contains("call", true) ||
                            data.contains("record", true) ||
                            rel.contains("call", true) ||
                            rel.contains("record", true)

                    val fileDigits = (name + data).replace(Regex("[^0-9]"), "")

                    // Check phone number match
                    var numberMatched = false
                    if (variants.isNotEmpty()) {
                        for (variant in variants) {
                            if (fileDigits.contains(variant) || name.contains(variant)) {
                                numberMatched = true
                                break
                            }
                        }
                    }

                    // Check time window match
                    val timeMatched = if (callStartTimeMs > 0 || callEndTimeMs > 0) {
                        val refStart = if (callStartTimeMs > 0) callStartTimeMs - (180 * 1000L) else (callEndTimeMs - 240 * 1000L)
                        val refEnd = (if (callEndTimeMs > 0) callEndTimeMs else callStartTimeMs) + (240 * 1000L)
                        modMs in refStart..refEnd
                    } else false

                    if (numberMatched || (isCallRelated && timeMatched) || (isCallRelated && Math.abs(System.currentTimeMillis() - modMs) < 180 * 1000L)) {
                        Log.d(TAG, "Matched MediaStore item: id=$id, name=$name, size=$size")
                        val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                        val copiedPath = copyUriToAppStorage(context, contentUri, name.ifBlank { "recording_${id}.m4a" }, number)
                        if (copiedPath != null) return copiedPath
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
     * Fallback: finds newest call recording created within the last 3 minutes across storage or MediaStore.
     */
    private fun findNewestCallRecording(context: Context): String? {
        val now = System.currentTimeMillis()

        // 1. Check directory files
        val candidateFiles = mutableListOf<File>()
        for (dirPath in BASE_SEARCH_DIRS) {
            val dir = File(dirPath)
            if (dir.exists() && dir.isDirectory) {
                collectAudioFiles(dir, candidateFiles, 0)
            }
        }
        val newestFile = candidateFiles.filter {
            Math.abs(now - it.lastModified()) < 180 * 1000L
        }.maxByOrNull { it.lastModified() }

        if (newestFile != null) {
            return backupFileToAppStorage(context, newestFile, "latest_call")
        }

        // 2. Check MediaStore newest audio
        try {
            val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_MODIFIED
            )
            val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC LIMIT 5"
            context.contentResolver.query(uri, projection, null, null, sortOrder)?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val nameIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val modIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idIdx)
                    val name = cursor.getString(nameIdx) ?: ""
                    val modMs = cursor.getLong(modIdx) * 1000L

                    if (Math.abs(now - modMs) < 180 * 1000L && isAudioFileName(name)) {
                        val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                        return copyUriToAppStorage(context, contentUri, name, "recent_call")
                    }
                }
            }
        } catch (_: Exception) {}

        return null
    }

    /**
     * Copies an audio Uri directly into the app's protected storage:
     * /Android/data/com.example.call_logger/files/recordings/
     */
    fun copyUriToAppStorage(context: Context, contentUri: Uri, originalName: String, number: String): String? {
        return try {
            val appRecordingsDir = File(context.getExternalFilesDir(null), "recordings").apply {
                if (!exists()) mkdirs()
            }
            val safeNumber = number.replace(Regex("[^0-9+]"), "").ifEmpty { "call" }
            val ext = originalName.substringAfterLast('.', "m4a").lowercase()
            val backupFileName = "backup_${safeNumber}_${System.currentTimeMillis()}.$ext"
            val destFile = File(appRecordingsDir, backupFileName)

            context.contentResolver.openInputStream(contentUri)?.use { input ->
                destFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }

            if (destFile.exists() && destFile.length() > 50) {
                Log.d(TAG, "Successfully copied from Uri: ${destFile.absolutePath} (${destFile.length()} bytes)")
                destFile.absolutePath
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy from Uri: ${e.message}", e)
            null
        }
    }

    fun backupToAppStorage(context: Context, sourceFile: File, number: String): String =
        backupFileToAppStorage(context, sourceFile, number)

    /**
     * Copies a local File into the app's protected storage:
     * /Android/data/com.example.call_logger/files/recordings/
     */
    fun backupFileToAppStorage(context: Context, sourceFile: File, number: String): String {
        return try {
            if (!sourceFile.exists() || sourceFile.length() < 50) {
                return sourceFile.absolutePath
            }

            val appRecordingsDir = File(context.getExternalFilesDir(null), "recordings").apply {
                if (!exists()) mkdirs()
            }

            val safeNumber = number.replace(Regex("[^0-9+]"), "").ifEmpty { "call" }
            val extension = sourceFile.extension.ifEmpty { "m4a" }
            val backupFileName = "backup_${safeNumber}_${System.currentTimeMillis()}.$extension"
            val destFile = File(appRecordingsDir, backupFileName)

            sourceFile.copyTo(destFile, overwrite = true)
            Log.d(TAG, "Successfully copied and backed up to: ${destFile.absolutePath}")
            destFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy recording: ${e.message}", e)
            sourceFile.absolutePath
        }
    }

    /**
     * Recursively collects audio files up to maxDepth.
     */
    private fun collectAudioFiles(dir: File, list: MutableList<File>, depth: Int = 0) {
        if (depth > 4 || !dir.exists() || !dir.isDirectory) return
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

    fun isAudioFile(file: File): Boolean = isAudioFileName(file.name)

    fun isAudioFileName(name: String): Boolean {
        val ext = name.substringAfterLast('.', "").lowercase()
        return ext == "m4a" || ext == "wav" || ext == "mp3" || ext == "amr" || ext == "aac" || ext == "ogg" || ext == "3gp"
    }

    /**
     * Scans and returns all available audio files across all device recording directories and MediaStore.
     */
    fun scanAllNativeRecordings(context: Context? = null): List<Map<String, Any>> {
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

        // Also query MediaStore if context provided
        if (context != null) {
            try {
                val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                val projection = arrayOf(
                    MediaStore.Audio.Media._ID,
                    MediaStore.Audio.Media.DISPLAY_NAME,
                    MediaStore.Audio.Media.DATE_MODIFIED,
                    MediaStore.Audio.Media.SIZE,
                    MediaStore.Audio.Media.DATA
                )
                context.contentResolver.query(uri, projection, null, null, "${MediaStore.Audio.Media.DATE_MODIFIED} DESC LIMIT 50")?.use { cursor ->
                    val nameIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                    val modIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)
                    val sizeIdx = cursor.getColumnIndex(MediaStore.Audio.Media.SIZE)
                    val dataIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)

                    while (cursor.moveToNext()) {
                        val name = if (nameIdx >= 0) cursor.getString(nameIdx) ?: "" else ""
                        val data = if (dataIdx >= 0) cursor.getString(dataIdx) ?: "" else ""
                        val modMs = if (modIdx >= 0) cursor.getLong(modIdx) * 1000L else 0L
                        val size = if (sizeIdx >= 0) cursor.getLong(sizeIdx) else 0L

                        if (isAudioFileName(name) && result.none { it["path"] == data }) {
                            result.add(
                                mapOf(
                                    "path" to data,
                                    "name" to name,
                                    "extension" to name.substringAfterLast('.', "m4a").lowercase(),
                                    "size" to size,
                                    "lastModified" to modMs
                                )
                            )
                        }
                    }
                }
            } catch (_: Exception) {}
        }

        return result.sortedByDescending { (it["lastModified"] as? Long) ?: 0L }
    }
}
