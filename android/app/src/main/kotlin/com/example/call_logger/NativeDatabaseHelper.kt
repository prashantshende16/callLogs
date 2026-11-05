package com.example.call_logger

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import android.provider.CallLog
import android.provider.ContactsContract
import android.util.Log

/**
 * NativeDatabaseHelper
 *
 * Provides native SQLite access for "Call Log Keeper" to "call_log_keeper.db".
 * Stores transparent personal call history backups shared with the Flutter UI.
 */
class NativeDatabaseHelper(private val context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {

    companion object {
        private const val TAG = "NativeDatabaseHelper"
        const val DATABASE_NAME = "call_log_keeper.db"
        const val DATABASE_VERSION = 1

        const val TABLE_CALL_RECORDS = "call_records"
        const val COL_ID = "id"
        const val COL_NUMBER = "number"
        const val COL_NAME = "name"
        const val COL_TYPE = "type"
        const val COL_DATE = "date"
        const val COL_DURATION = "duration"
        const val COL_AUDIO_PATH = "audio_path"

        @Volatile
        private var instance: NativeDatabaseHelper? = null

        fun getInstance(context: Context): NativeDatabaseHelper {
            return instance ?: synchronized(this) {
                instance ?: NativeDatabaseHelper(context.applicationContext).also { instance = it }
            }
        }

        fun getContactName(context: Context, number: String?): String? = resolveContactName(context, number)

        fun resolveContactName(context: Context, number: String?): String? {
            if (number.isNullOrBlank()) return null
            return try {
                val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number.trim()))
                context.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error looking up contact name: ${e.message}")
                null
            }
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_CALL_RECORDS (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_NUMBER TEXT NOT NULL,
                $COL_NAME TEXT,
                $COL_TYPE INTEGER NOT NULL,
                $COL_DATE INTEGER NOT NULL,
                $COL_DURATION INTEGER NOT NULL,
                $COL_AUDIO_PATH TEXT,
                UNIQUE($COL_NUMBER, $COL_DATE) ON CONFLICT REPLACE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_call_records_date ON $TABLE_CALL_RECORDS ($COL_DATE DESC)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_call_records_number ON $TABLE_CALL_RECORDS ($COL_NUMBER)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        try {
            db.execSQL("ALTER TABLE $TABLE_CALL_RECORDS ADD COLUMN $COL_AUDIO_PATH TEXT")
        } catch (_: Exception) {
            // Column already exists
        }
    }

    /**
     * STEP 1: Records the call AT THE EXACT MOMENT it starts / rings / dials.
     * Inserts an initial record with duration = 0 so the number is NEVER lost even
     * if the call is rejected, cancelled, cut immediately, or deleted from dialer.
     */
    fun recordCallStart(number: String, type: Int, timestamp: Long): Long {
        if (number.isBlank() || number.equals("Unknown", ignoreCase = true)) {
            Log.d(TAG, "recordCallStart skipped for blank/unknown number")
            return -1L
        }

        val cleanNumber = number.trim()
        val db = writableDatabase

        return try {
            // Check if a placeholder for this number was already inserted within the last 15 seconds
            val minDate = timestamp - 15_000L
            val maxDate = timestamp + 15_000L
            db.query(
                TABLE_CALL_RECORDS,
                arrayOf(COL_ID),
                "$COL_NUMBER = ? AND $COL_DATE >= ? AND $COL_DATE <= ?",
                arrayOf(cleanNumber, minDate.toString(), maxDate.toString()),
                null,
                null,
                "$COL_DATE DESC LIMIT 1"
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val existingId = cursor.getLong(0)
                    Log.d(TAG, "recordCallStart: Found existing placeholder record id=$existingId for $cleanNumber")
                    return existingId
                }
            }

            // Insert new initial record
            val resolvedName = resolveContactName(context, cleanNumber)
            val values = ContentValues().apply {
                put(COL_NUMBER, cleanNumber)
                put(COL_NAME, resolvedName)
                put(COL_TYPE, type) // 1 = Incoming, 2 = Outgoing
                put(COL_DATE, timestamp)
                put(COL_DURATION, 0L)
            }

            val id = db.insertWithOnConflict(
                TABLE_CALL_RECORDS,
                null,
                values,
                SQLiteDatabase.CONFLICT_REPLACE
            )
            Log.d(TAG, "STEP 1 SUCCESS: Inserted initial call record rowId=$id, number=$cleanNumber, type=$type, date=$timestamp")
            id
        } catch (e: Exception) {
            Log.e(TAG, "Failed in recordCallStart: ${e.message}", e)
            -1L
        }
    }

    /**
     * STEP 2: Updates an existing in-progress call record or inserts the final confirmed call.
     * Matches any call record for this number within a 45-second window.
     */
    fun recordCallEndOrUpdate(
        number: String,
        callDate: Long,
        duration: Long,
        type: Int,
        cachedName: String? = null
    ): Long {
        if (number.isBlank()) return -1L
        val cleanNumber = number.trim()
        val db = writableDatabase

        return try {
            val resolvedName = if (!cachedName.isNullOrBlank()) cachedName else resolveContactName(context, cleanNumber)

            // Look for existing placeholder record within 45 seconds of callDate
            val minDate = callDate - 45_000L
            val maxDate = callDate + 45_000L
            var existingId = -1L

            db.query(
                TABLE_CALL_RECORDS,
                arrayOf(COL_ID),
                "$COL_NUMBER = ? AND $COL_DATE >= ? AND $COL_DATE <= ?",
                arrayOf(cleanNumber, minDate.toString(), maxDate.toString()),
                null,
                null,
                "$COL_DATE DESC LIMIT 1"
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    existingId = cursor.getLong(0)
                }
            }

            if (existingId > 0) {
                // Update existing record with final confirmed duration, type, and date
                val updateValues = ContentValues().apply {
                    put(COL_DATE, callDate)
                    put(COL_DURATION, duration)
                    put(COL_TYPE, type)
                    if (resolvedName != null) {
                        put(COL_NAME, resolvedName)
                    }
                }
                db.update(
                    TABLE_CALL_RECORDS,
                    updateValues,
                    "$COL_ID = ?",
                    arrayOf(existingId.toString())
                )
                Log.d(TAG, "STEP 2 SUCCESS: Updated call record id=$existingId, duration=$duration, type=$type, number=$cleanNumber")
                existingId
            } else {
                // Insert new record if no placeholder existed
                val insertValues = ContentValues().apply {
                    put(COL_NUMBER, cleanNumber)
                    put(COL_NAME, resolvedName)
                    put(COL_TYPE, type)
                    put(COL_DATE, callDate)
                    put(COL_DURATION, duration)
                }
                val newId = db.insertWithOnConflict(
                    TABLE_CALL_RECORDS,
                    null,
                    insertValues,
                    SQLiteDatabase.CONFLICT_REPLACE
                )
                Log.d(TAG, "STEP 2 SUCCESS: Inserted new confirmed call record id=$newId, duration=$duration, number=$cleanNumber")
                newId
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed in recordCallEndOrUpdate: ${e.message}", e)
            -1L
        }
    }

    /**
     * Fallback calculation in case system CallLog was wiped or not written yet.
     */
    fun updateFallbackDuration(number: String, callStartTime: Long, duration: Long): Int {
        if (number.isBlank()) return 0
        return try {
            val db = writableDatabase
            val minDate = callStartTime - 30_000L
            val values = ContentValues().apply {
                put(COL_DURATION, duration)
            }
            db.update(
                TABLE_CALL_RECORDS,
                values,
                "$COL_NUMBER = ? AND $COL_DATE >= ? AND $COL_DURATION = 0",
                arrayOf(number.trim(), minDate.toString())
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error in updateFallbackDuration: ${e.message}", e)
            0
        }
    }

    /**
     * Standard insertion matching unique constraint (number, date).
     */
    fun insertCallRecord(number: String, name: String?, type: Int, date: Long, duration: Long): Long {
        return recordCallEndOrUpdate(number, date, duration, type, name)
    }

    /**
     * Polls the system CallLog for recent calls (ended or started within the last 60 seconds).
     * Returns the count of calls captured.
     */
    fun syncRecentCallFromSystem(referenceEndTime: Long = System.currentTimeMillis()): Int {
        var count = 0
        try {
            val projection = arrayOf(
                CallLog.Calls.NUMBER,
                CallLog.Calls.TYPE,
                CallLog.Calls.DURATION,
                CallLog.Calls.DATE,
                CallLog.Calls.CACHED_NAME
            )
            val sortOrder = "${CallLog.Calls.DATE} DESC LIMIT 5"
            context.contentResolver.query(CallLog.Calls.CONTENT_URI, projection, null, null, sortOrder)?.use { cursor ->
                val numIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
                val typeIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.TYPE)
                val durIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DURATION)
                val dateIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DATE)
                val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)

                val now = System.currentTimeMillis()
                while (cursor.moveToNext()) {
                    val number = cursor.getString(numIdx) ?: "Unknown"
                    val type = cursor.getInt(typeIdx)
                    val duration = cursor.getLong(durIdx)
                    val date = cursor.getLong(dateIdx)
                    val cachedName = if (nameIdx >= 0) cursor.getString(nameIdx) else null

                    val callEndTime = date + (duration * 1000L)
                    val endDiff = Math.abs(referenceEndTime - callEndTime)
                    val startDiff = Math.abs(referenceEndTime - date)
                    val age = now - date

                    // Match if call occurred within the last 60 seconds
                    val isRecent = endDiff < 60_000L || startDiff < 60_000L || age < 60_000L

                    if (isRecent) {
                        val id = recordCallEndOrUpdate(number, date, duration, type, cachedName)
                        if (id > 0) {
                            count++
                            Log.d(TAG, "syncRecentCallFromSystem captured/updated: number=$number, duration=$duration, type=$type")
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in syncRecentCallFromSystem: ${e.message}", e)
        }
        return count
    }

    /**
     * Syncs historical call logs from Android system CallLog into call_records.
     */
    fun syncHistoricalCalls(limit: Int = 100): Int {
        var count = 0
        try {
            val projection = arrayOf(
                CallLog.Calls.NUMBER,
                CallLog.Calls.TYPE,
                CallLog.Calls.DURATION,
                CallLog.Calls.DATE,
                CallLog.Calls.CACHED_NAME
            )
            val sortOrder = "${CallLog.Calls.DATE} DESC LIMIT $limit"
            context.contentResolver.query(CallLog.Calls.CONTENT_URI, projection, null, null, sortOrder)?.use { cursor ->
                val numIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
                val typeIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.TYPE)
                val durIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DURATION)
                val dateIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DATE)
                val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)

                while (cursor.moveToNext()) {
                    val number = cursor.getString(numIdx) ?: "Unknown"
                    val type = cursor.getInt(typeIdx)
                    val duration = cursor.getLong(durIdx)
                    val date = cursor.getLong(dateIdx)
                    val cachedName = if (nameIdx >= 0) cursor.getString(nameIdx) else null

                    val id = recordCallEndOrUpdate(number, date, duration, type, cachedName)
                    if (id > 0) count++
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing historical calls: ${e.message}", e)
        }
        return count
    }

    /**
     * Updates the audio recording file path for a specific call record.
     * Matches by number and timestamp window, or falls back to the most recent call.
     */
    fun updateAudioPath(number: String?, date: Long, audioPath: String): Int {
        if (audioPath.isBlank()) return 0
        return try {
            val db = writableDatabase
            val values = ContentValues().apply {
                put(COL_AUDIO_PATH, audioPath)
            }

            var rows = 0
            if (!number.isNullOrBlank() && number != "Unknown") {
                val cleanNumber = number.trim()
                val minDate = if (date > 0) date - 60_000L else System.currentTimeMillis() - 120_000L
                val maxDate = if (date > 0) date + 60_000L else System.currentTimeMillis() + 120_000L

                rows = db.update(
                    TABLE_CALL_RECORDS,
                    values,
                    "$COL_NUMBER = ? AND $COL_DATE >= ? AND $COL_DATE <= ?",
                    arrayOf(cleanNumber, minDate.toString(), maxDate.toString())
                )
            }

            if (rows == 0 && date > 0) {
                // Try matching by date within 30s
                val minDate = date - 30_000L
                val maxDate = date + 30_000L
                rows = db.update(
                    TABLE_CALL_RECORDS,
                    values,
                    "$COL_DATE >= ? AND $COL_DATE <= ?",
                    arrayOf(minDate.toString(), maxDate.toString())
                )
            }

            if (rows == 0) {
                // Fallback: update newest call record
                val cursor = db.query(
                    TABLE_CALL_RECORDS,
                    arrayOf(COL_ID),
                    null,
                    null,
                    null,
                    null,
                    "$COL_DATE DESC LIMIT 1"
                )
                cursor?.use {
                    if (it.moveToFirst()) {
                        val latestId = it.getLong(0)
                        rows = db.update(
                            TABLE_CALL_RECORDS,
                            values,
                            "$COL_ID = ?",
                            arrayOf(latestId.toString())
                        )
                    }
                }
            }

            Log.d(TAG, "updateAudioPath: Updated $rows rows with audio_path=$audioPath")
            rows
        } catch (e: Exception) {
            Log.e(TAG, "Failed in updateAudioPath: ${e.message}", e)
            0
        }
    }
}
