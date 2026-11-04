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
 * Provides native Kotlin SQLite access to the same 'call_logger.db' database used by Flutter/sqflite.
 * Ensures that calls are immediately saved 24/7 even when the Flutter application is CLOSED,
 * killed from recent apps, or when the user deletes the call log from the phone dialer.
 */
class NativeDatabaseHelper(private val context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {

    companion object {
        private const val TAG = "NativeDatabaseHelper"
        const val DATABASE_NAME = "call_logger.db"
        const val DATABASE_VERSION = 3

        const val TABLE_CALL_RECORDS = "call_records"
        const val COL_ID = "id"
        const val COL_CALLER_NUMBER = "caller_number"
        const val COL_CALLER_NAME = "caller_name"
        const val COL_RECEIVER_NUMBER = "receiver_number"
        const val COL_CALL_TYPE = "call_type"
        const val COL_CALL_STATUS = "call_status"
        const val COL_START_TIME = "start_time"
        const val COL_END_TIME = "end_time"
        const val COL_DURATION_SECONDS = "duration_seconds"
        const val COL_SIM_SLOT = "sim_slot"
        const val COL_AUDIO_PATH = "audio_path"
        const val COL_CREATED_AT = "created_at"

        @Volatile
        private var instance: NativeDatabaseHelper? = null

        fun getInstance(context: Context): NativeDatabaseHelper {
            return instance ?: synchronized(this) {
                instance ?: NativeDatabaseHelper(context.applicationContext).also { instance = it }
            }
        }

        /**
         * Resolves contact display name from Android ContactsContract by phone number.
         */
        fun getContactName(context: Context, phoneNumber: String?): String? {
            if (phoneNumber.isNullOrBlank() || phoneNumber.equals("Unknown", ignoreCase = true)) {
                return null
            }
            return try {
                val uri = Uri.withAppendedPath(
                    ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                    Uri.encode(phoneNumber.trim())
                )
                val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
                context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                        if (nameIdx >= 0) {
                            cursor.getString(nameIdx)
                        } else null
                    } else null
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error looking up contact name for $phoneNumber: ${e.message}")
                null
            }
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_CALL_RECORDS (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_CALLER_NUMBER TEXT NOT NULL,
                $COL_CALLER_NAME TEXT,
                $COL_RECEIVER_NUMBER TEXT NOT NULL,
                $COL_CALL_TYPE TEXT NOT NULL,
                $COL_CALL_STATUS TEXT NOT NULL,
                $COL_START_TIME INTEGER NOT NULL,
                $COL_END_TIME INTEGER NOT NULL,
                $COL_DURATION_SECONDS INTEGER NOT NULL,
                $COL_SIM_SLOT TEXT,
                $COL_AUDIO_PATH TEXT,
                $COL_CREATED_AT INTEGER NOT NULL,
                UNIQUE($COL_CALLER_NUMBER, $COL_START_TIME) ON CONFLICT IGNORE
            )
            """.trimIndent()
        )

        db.execSQL("CREATE INDEX IF NOT EXISTS idx_call_records_start_time ON $TABLE_CALL_RECORDS ($COL_START_TIME DESC)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_call_records_caller ON $TABLE_CALL_RECORDS ($COL_CALLER_NUMBER)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_call_records_type ON $TABLE_CALL_RECORDS ($COL_CALL_TYPE)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            try {
                db.execSQL("ALTER TABLE $TABLE_CALL_RECORDS ADD COLUMN $COL_AUDIO_PATH TEXT;")
            } catch (e: Exception) {
                Log.w(TAG, "Column $COL_AUDIO_PATH might already exist: ${e.message}")
            }
        }
        if (oldVersion < 3) {
            try {
                db.execSQL("ALTER TABLE $TABLE_CALL_RECORDS ADD COLUMN $COL_CALLER_NAME TEXT;")
            } catch (e: Exception) {
                Log.w(TAG, "Column $COL_CALLER_NAME might already exist: ${e.message}")
            }
        }
    }

    /**
     * Inserts a call record directly into SQLite from the native background receiver.
     */
    fun insertCallRecord(
        callerNumber: String,
        receiverNumber: String,
        callType: String,
        callStatus: String,
        startTime: Long,
        endTime: Long,
        durationSeconds: Int,
        simSlot: String?,
        audioPath: String?,
        callerName: String? = null
    ): Long {
        return try {
            val db = writableDatabase
            val resolvedName = if (!callerName.isNullOrBlank()) {
                callerName
            } else {
                getContactName(context, callerNumber)
            }

            val values = ContentValues().apply {
                put(COL_CALLER_NUMBER, callerNumber)
                put(COL_CALLER_NAME, resolvedName)
                put(COL_RECEIVER_NUMBER, receiverNumber)
                put(COL_CALL_TYPE, callType)
                put(COL_CALL_STATUS, callStatus)
                put(COL_START_TIME, startTime)
                put(COL_END_TIME, endTime)
                put(COL_DURATION_SECONDS, durationSeconds)
                put(COL_SIM_SLOT, simSlot)
                put(COL_AUDIO_PATH, audioPath)
                put(COL_CREATED_AT, System.currentTimeMillis())
            }

            db.insertWithOnConflict(
                TABLE_CALL_RECORDS,
                null,
                values,
                SQLiteDatabase.CONFLICT_IGNORE
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to insert call record native: ${e.message}")
            -1L
        }
    }

    /**
     * Reads recent calls from Android's system CallLog (CallLog.Calls)
     * and copies them directly into local SQLite database (call_records).
     * Automatically resolves contact names and matches/copies audio recordings.
     */
    fun syncLatestFromSystemCallLog(limit: Int = 10): Int {
        var syncedCount = 0
        try {
            val contentResolver = context.contentResolver
            val projection = arrayOf(
                CallLog.Calls._ID,
                CallLog.Calls.NUMBER,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION,
                CallLog.Calls.TYPE,
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.PHONE_ACCOUNT_ID
            )

            val sortOrder = "${CallLog.Calls.DATE} DESC LIMIT $limit"
            contentResolver.query(CallLog.Calls.CONTENT_URI, projection, null, null, sortOrder)?.use { cursor ->
                val numIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
                val dateIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DATE)
                val durIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DURATION)
                val typeIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.TYPE)
                val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val simIdx = cursor.getColumnIndex(CallLog.Calls.PHONE_ACCOUNT_ID)

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

                val db = writableDatabase

                while (cursor.moveToNext()) {
                    val rawNum = cursor.getString(numIdx)
                    val logNum = if (!rawNum.isNullOrBlank()) rawNum.trim() else "Unknown"
                    val logDate = cursor.getLong(dateIdx)
                    val logDur = cursor.getInt(durIdx)
                    val logType = cursor.getInt(typeIdx)
                    val cachedName = if (nameIdx >= 0) cursor.getString(nameIdx) else null
                    val simId = if (simIdx >= 0) cursor.getString(simIdx) else null

                    val mappedType = when (logType) {
                        CallLog.Calls.INCOMING_TYPE -> "incoming"
                        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        CallLog.Calls.REJECTED_TYPE -> "rejected"
                        CallLog.Calls.BLOCKED_TYPE -> "rejected"
                        else -> "incoming"
                    }
                    val mappedStatus = if (mappedType == "missed" || mappedType == "rejected") "missed" else "ended"

                    val resolvedName = if (!cachedName.isNullOrBlank()) {
                        cachedName.trim()
                    } else {
                        getContactName(context, logNum)
                    }

                    val simSlot = if (!simId.isNullOrBlank()) "SIM $simId" else null
                    val endTime = logDate + (logDur * 1000L)

                    // Find and link audio recording file if available
                    val audioPath = NativeAudioScanner.findRecordingForCall(context, logNum, logDate, endTime)

                    // 1. Purge any obsolete placeholder 'Unknown' entries matching approximately this time
                    db.delete(
                        TABLE_CALL_RECORDS,
                        "$COL_CALLER_NUMBER = 'Unknown' AND ABS($COL_START_TIME - ?) < 180000",
                        arrayOf(logDate.toString())
                    )

                    // 2. Check if a record already exists with same number and approximate start time (within 30s)
                    val checkCursor = db.query(
                        TABLE_CALL_RECORDS,
                        arrayOf(COL_ID, COL_AUDIO_PATH),
                        "$COL_CALLER_NUMBER = ? AND ABS($COL_START_TIME - ?) < 30000",
                        arrayOf(logNum, logDate.toString()),
                        null, null, null
                    )

                    val exists = checkCursor.use { it.moveToFirst() }

                    if (exists) {
                        val values = ContentValues().apply {
                            if (!resolvedName.isNullOrBlank()) put(COL_CALLER_NAME, resolvedName)
                            put(COL_DURATION_SECONDS, logDur)
                            put(COL_END_TIME, endTime)
                            put(COL_CALL_TYPE, mappedType)
                            put(COL_CALL_STATUS, mappedStatus)
                            if (audioPath != null) put(COL_AUDIO_PATH, audioPath)
                        }
                        db.update(
                            TABLE_CALL_RECORDS,
                            values,
                            "$COL_CALLER_NUMBER = ? AND ABS($COL_START_TIME - ?) < 30000",
                            arrayOf(logNum, logDate.toString())
                        )
                    } else {
                        val values = ContentValues().apply {
                            put(COL_CALLER_NUMBER, logNum)
                            put(COL_CALLER_NAME, resolvedName)
                            put(COL_RECEIVER_NUMBER, receiverNumber)
                            put(COL_CALL_TYPE, mappedType)
                            put(COL_CALL_STATUS, mappedStatus)
                            put(COL_START_TIME, logDate)
                            put(COL_END_TIME, endTime)
                            put(COL_DURATION_SECONDS, logDur)
                            put(COL_SIM_SLOT, simSlot)
                            put(COL_AUDIO_PATH, audioPath)
                            put(COL_CREATED_AT, System.currentTimeMillis())
                        }
                        db.insertWithOnConflict(TABLE_CALL_RECORDS, null, values, SQLiteDatabase.CONFLICT_REPLACE)
                        syncedCount++
                    }
                    Log.d(TAG, "Copied CallLog into local SQLite: num=$logNum, name=$resolvedName, type=$mappedType, dur=$logDur, audio=$audioPath")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing CallLog to local SQLite: ${e.message}", e)
        }
        return syncedCount
    }

    /**
     * Cleans up any orphan 'Unknown' records that had 0 duration or were left from incomplete broadcasts,
     * and re-syncs recent real calls from system CallLog.
     */
    fun cleanUnknownRecords() {
        try {
            val db = writableDatabase
            db.delete(TABLE_CALL_RECORDS, "$COL_CALLER_NUMBER = 'Unknown'", null)
            syncLatestFromSystemCallLog(15)
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning unknown records: ${e.message}")
        }
    }

    /**
     * Updates the audio backup path for a call matching caller number and timestamp.
     */
    fun updateAudioPath(callerNumber: String, startTime: Long, audioPath: String): Int {
        return try {
            val db = writableDatabase
            val values = ContentValues().apply {
                put(COL_AUDIO_PATH, audioPath)
            }

            var rows = db.update(
                TABLE_CALL_RECORDS,
                values,
                "$COL_CALLER_NUMBER = ? AND ABS($COL_START_TIME - ?) < 60000",
                arrayOf(callerNumber, startTime.toString())
            )

            if (rows == 0) {
                db.execSQL(
                    """
                    UPDATE $TABLE_CALL_RECORDS 
                    SET $COL_AUDIO_PATH = ? 
                    WHERE $COL_ID = (SELECT $COL_ID FROM $TABLE_CALL_RECORDS ORDER BY $COL_START_TIME DESC LIMIT 1)
                    """.trimIndent(),
                    arrayOf(audioPath)
                )
                rows = 1
            }

            Log.d(TAG, "Updated audio path native -> $audioPath (rows affected: $rows)")
            rows
        } catch (e: Exception) {
            Log.e(TAG, "Error updating audio path native: ${e.message}", e)
            0
        }
    }
}
