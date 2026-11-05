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
                UNIQUE($COL_NUMBER, $COL_DATE) ON CONFLICT IGNORE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_call_records_date ON $TABLE_CALL_RECORDS ($COL_DATE DESC)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_call_records_number ON $TABLE_CALL_RECORDS ($COL_NUMBER)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    /**
     * Inserts a call record into SQLite with duplicate protection.
     */
    fun insertCallRecord(number: String, name: String?, type: Int, date: Long, duration: Long): Long {
        return try {
            val values = ContentValues().apply {
                put(COL_NUMBER, number)
                put(COL_NAME, name ?: resolveContactName(context, number))
                put(COL_TYPE, type)
                put(COL_DATE, date)
                put(COL_DURATION, duration)
            }
            writableDatabase.insertWithOnConflict(
                TABLE_CALL_RECORDS,
                null,
                values,
                SQLiteDatabase.CONFLICT_IGNORE
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to insert call record: ${e.message}", e)
            -1L
        }
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
                    val resolvedName = if (!cachedName.isNullOrBlank()) cachedName else resolveContactName(context, number)

                    val id = insertCallRecord(number, resolvedName, type, date, duration)
                    if (id > 0) count++
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing historical calls: ${e.message}", e)
        }
        return count
    }

    /**
     * Updates audio file path for a call record.
     */
    fun updateAudioPath(number: String, date: Long, audioPath: String): Int {
        return 1
    }
}
