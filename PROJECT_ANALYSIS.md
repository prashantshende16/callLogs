# Call Log Keeper — Project Architecture & Implementation Document

---

## 1. Executive Summary

**Call Log Keeper** is a transparent, privacy-first personal call-history backup application built using **Flutter** and **Native Android Kotlin**.

The application is designed specifically for personal record-keeping, diagnostics, and transparent background backup:
- **Transparent Foreground Service**: Operates with a visible, persistent notification ("Call Log Keeper is running — Monitoring calls to keep your backup up to date") in strict adherence to Google Play foreground service policies (`FOREGROUND_SERVICE_PHONE_CALL`).
- **No App-Hiding or PIN Locks**: 100% transparent personal utility without cloaked icons, stealth mode, or access gatekeepers.
- **Direct Local SQLite Storage**: Backs up all confirmed call records locally on the user's device in `call_log_keeper.db`. Zero cloud transmission or external tracking.
- **Native Call End Detection**: Detects call termination via `TelephonyCallback` (Android 12+) and `PhoneStateListener` (pre-Android 12), waits a standard ~800ms delay for system `CallLog.Calls` to populate, and stores the confirmed record.

---

## 2. System Architecture & Flow

```mermaid
flowchart TD
    subgraph AndroidTelephony["Android System & Telephony Stack"]
        GSM["Cellular / GSM Hardware"] --> TM["TelephonyManager"]
        TM -->|TelephonyCallback / CallStateListener| CMS["CallMonitorService (Foreground Service)"]
        TM -->|Write finalized call at hangup| CL["System CallLog (CallLog.Calls)"]
        CONTACTS["Android Contacts Provider"]
    end

    subgraph NativeLayer["Call Log Keeper Native Layer (Kotlin)"]
        CMS -->|Ongoing Notification| NOTIF["Visible Notification: 'Call Log Keeper is running'"]
        CMS -->|CALL_STATE_IDLE after Ringing/Offhook| SYNC["syncLatestCallFromLog() (after 800ms)"]
        SYNC -->|Query latest completed record| CL
        SYNC -->|Resolve Display Name| CONTACTS
        SYNC -->|Insert record| NDB["NativeDatabaseHelper (call_log_keeper.db)"]
        CMS -->|notifyFlutterCallLogged()| MC["MethodChannel ('com.example.call_logger/monitor')"]
    end

    subgraph FlutterUI["Flutter Application (Dart)"]
        ROOT["RootGatekeeper"] -->|Permissions not granted| PERM["PermissionScreen (Transparent Rationale)"]
        ROOT -->|Permissions granted| HOME["HomeScreen (Material 3 Dashboard)"]
        HOME --> STATS["Stats Bar (Total, Incoming, Outgoing, Missed)"]
        HOME --> LIST["Call Records List (Real-time updates)"]
        HOME --> SETTINGS["SettingsScreen (Service Toggle & Manual Sync)"]
        SETTINGS -->|startMonitoring / stopMonitoring| MC
        MC -->|startForegroundService / stopService| CMS
        HOME <-->|Read & Filter records| FDB["DatabaseHelper (Sqflite)"]
        FDB <-->|Read / Write call_records| NDB
    end
```

---

## 3. Concrete Implementation Specifications

### 3.1. Call State Detection — `CallMonitorService.kt`
- **Class**: [`CallMonitorService`](file:///home/dev04/datagrid/flutter_project/AccessControl/android/app/src/main/kotlin/com/example/call_logger/CallMonitorService.kt)
- **Foreground Service Type**: `android:foregroundServiceType="phoneCall"`
- **Required Permission**: `android.permission.FOREGROUND_SERVICE_PHONE_CALL`
- **Notification**:
  - Channel ID: `call_log_keeper_channel`
  - Channel Name: `Call Log Keeper`
  - Title: `Call Log Keeper is running`
  - Text: `Monitoring calls to keep your backup up to date`
  - Small Icon: `ic_call_service`
- **Telephony Callback**:
  - Android 12+ (API 31+): `telephonyManager.registerTelephonyCallback(mainExecutor, CallStateListener)`
  - Pre-Android 12: `telephonyManager.listen(PhoneStateListener, LISTEN_CALL_STATE)`
- **State Transition**:
  - `RINGING` -> sets `wasRinging = true`
  - `OFFHOOK` -> call answered or outgoing call connected
  - `IDLE` -> when transitioning from non-IDLE state, waits 800ms for system `CallLog.Calls` to populate, calls `syncLatestCallFromLog(wasRinging)`, and notifies Flutter.

### 3.2. Reading Confirmed Call Record — `syncLatestCallFromLog`
```kotlin
private fun syncLatestCallFromLog(wasAnswered: Boolean) {
    val cursor = contentResolver.query(
        CallLog.Calls.CONTENT_URI, null, null, null,
        "${CallLog.Calls.DATE} DESC LIMIT 1"
    )
    cursor?.use {
        if (it.moveToFirst()) {
            val number = it.getString(it.getColumnIndexOrThrow(CallLog.Calls.NUMBER))
            val type = it.getInt(it.getColumnIndexOrThrow(CallLog.Calls.TYPE))
            val duration = it.getLong(it.getColumnIndexOrThrow(CallLog.Calls.DURATION))
            val date = it.getLong(it.getColumnIndexOrThrow(CallLog.Calls.DATE))
            val name = resolveContactName(number)
            NativeDatabaseHelper(this).insertCallRecord(number, name, type, date, duration)
        }
    }
}
```

### 3.3. SQLite Schema & Helpers — `call_log_keeper.db`
- **Database Name**: `call_log_keeper.db` (Version 1)
- **Table Name**: `call_records`
- **Schema**:
```sql
CREATE TABLE IF NOT EXISTS call_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    number TEXT NOT NULL,
    name TEXT,
    type INTEGER NOT NULL,
    date INTEGER NOT NULL,
    duration INTEGER NOT NULL,
    UNIQUE(number, date) ON CONFLICT IGNORE
);
CREATE INDEX IF NOT EXISTS idx_call_records_date ON call_records (date DESC);
CREATE INDEX IF NOT EXISTS idx_call_records_number ON call_records (number);
```
- **Call Type Mapping**:
  - `1`: Incoming
  - `2`: Outgoing
  - `3`: Missed
  - `5`: Rejected
  - `6`: Blocked

### 3.4. Manifest Entries — `AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.READ_CALL_LOG" />
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
<uses-permission android:name="android.permission.READ_CONTACTS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<service
    android:name=".CallMonitorService"
    android:enabled="true"
    android:exported="false"
    android:foregroundServiceType="phoneCall" />
```

### 3.5. Flutter UI & Features
1. **Onboarding & Permissions (`PermissionScreen`)**:
   - Clear breakdown of why each permission is needed (`READ_CALL_LOG`, `READ_PHONE_STATE`, `READ_CONTACTS`, `POST_NOTIFICATIONS`).
   - 100% local storage statement.
2. **Main Dashboard (`HomeScreen`)**:
   - App Bar with dynamic active/paused monitoring status badge.
   - Summary stats counters (Total, Incoming, Outgoing, Missed).
   - Search bar (by name or number) & quick filters (`All`, `Incoming`, `Outgoing`, `Missed`).
   - Pull-to-refresh to manually sync device call logs.
   - Clean list tile displaying contact avatar, formatted call type badge, date/time, and talk duration.
3. **Settings (`SettingsScreen`)**:
   - SwitchListTile to start/stop the ongoing `CallMonitorService` via MethodChannel.
   - Manual one-tap call history sync button.
   - Export backup to CSV.
   - Data clearing and privacy notice.

---

## 4. Privacy & Compliance

- **No Cloaking**: App icon and labels are clearly branded as "Call Log Keeper".
- **No Access Gates**: Does not require PINs or passwords.
- **Continuous Notification**: The foreground service displays an ongoing notification while monitoring is active, satisfying Android 14 policy requirements for phone call foreground services.
- **Zero Remote Exfiltration**: Operates 100% locally.
