# Call Logger (Flutter - Android Only)

An automated Call Monitoring and SQLite Logging application for Android built with Flutter.

Call Logger listens to incoming and outgoing call states in the background 24/7 via an Android foreground service, extracts accurate caller and receiver numbers, determines call duration and state transitions, and persists structured logs into a local SQLite database with duplicate prevention.

---

## Key Features

1. **Permission Onboarding & Diagnostics**:
   - On first launch, presents an explanation card for `READ_PHONE_STATE`, `READ_PHONE_NUMBERS`, `READ_CALL_LOG`, and `POST_NOTIFICATIONS` (Android 13+).
   - Uses `permission_handler` to request permissions; handles permanent denials with a direct button to system App Settings.

2. **Continuous Background Call Monitoring**:
   - Native Kotlin `CallStateReceiver` listening to `android.intent.action.PHONE_STATE`.
   - `CallMonitorService` running as an Android 14 compliant foreground service (`specialUse` / `dataSync`) with a persistent notification.
   - `BootReceiver` listening to `android.intent.action.BOOT_COMPLETED` and `android.intent.action.QUICKBOOT_POWERON` to automatically resume monitoring after device reboot.
   - Accurately captures call state transitions: `RINGING` $\rightarrow$ `OFFHOOK` (answered) $\rightarrow$ `IDLE` (ended/missed/rejected).
   - Reconciles finalized duration and timestamps with the system `CallLog` content provider.

3. **Receiver Number Detection & Manual Fallback**:
   - Queries `SubscriptionManager` and `TelephonyManager` for SIM card line 1 phone numbers.
   - Because many mobile carriers do not flash phone numbers to SIM cards for privacy, the app provides a manual phone number configuration in Settings.

4. **Robust SQLite Local Storage**:
   - Built on `sqflite` and `path` with a `DatabaseHelper` singleton and schema versioning (`onCreate`, `onUpgrade`).
   - Unique constraint on `(caller_number, start_time)` with `ON CONFLICT IGNORE` to prevent duplicate records.
   - Indexed columns (`start_time`, `caller_number`, `call_type`) for fast lookups.
   - One-time historical call log sync on first launch or on-demand from Settings.

5. **Intuitive UI & Analysis**:
   - **Home Screen**: Real-time list of call records sorted newest-first, summary statistics bar, pull-to-refresh, phone number search, and date & call type filters.
   - **Call Detail Screen**: Comprehensive view of caller, receiver, call duration, SIM slot, timestamps, database ID, and one-tap number copying.
   - **Swipe-to-Delete**: Swipe left with confirmation dialog to delete individual records.
   - **Settings Screen**: Toggle background service on/off, change own number, export to CSV via system share sheet, and purge database.

---

## Project Structure

```
AccessControl/
├── pubspec.yaml
├── README.md
├── android/
│   ├── build.gradle
│   ├── settings.gradle
│   ├── gradle.properties
│   └── app/
│       ├── build.gradle
│       └── src/main/
│           ├── AndroidManifest.xml
│           ├── kotlin/com/example/call_logger/
│           │   ├── MainActivity.kt        # MethodChannel & device number detection
│           │   ├── CallMonitorService.kt  # Android 14 Foreground Service
│           │   ├── CallStateReceiver.kt   # Phone state transition state machine
│           │   └── BootReceiver.kt        # Auto-restart on device reboot
│           └── res/
│               ├── drawable/ic_call_service.xml
│               └── values/styles.xml
└── lib/
    ├── main.dart                          # Root app & permission gatekeeper
    ├── models/
    │   └── call_record.dart               # CallRecord data model
    ├── services/
    │   ├── database_helper.dart           # SQLite singleton & CRUD methods
    │   ├── call_log_service.dart          # System CallLog provider query & sync
    │   ├── native_call_service.dart       # Kotlin MethodChannel interface
    │   ├── permission_service.dart        # Runtime permission checks
    │   └── export_service.dart            # CSV generation and sharing
    ├── providers/
    │   ├── call_record_provider.dart      # Call records state & real-time events
    │   ├── settings_provider.dart         # Preferences & monitoring toggle
    │   └── permission_provider.dart       # Onboarding permission lifecycle
    ├── screens/
    │   ├── permission_screen.dart         # First launch permission explanation
    │   ├── home_screen.dart               # Records list, stats & filters
    │   ├── call_detail_screen.dart        # Detailed call inspector
    │   └── settings_screen.dart           # Service toggle, own number & CSV export
    └── widgets/
        ├── call_record_tile.dart          # List tile with swipe-to-delete
        ├── call_type_badge.dart           # Color-coded badge (Incoming/Outgoing/Missed)
        ├── filter_sheet.dart              # Modal filter by type & date presets
        └── search_bar_widget.dart         # Live phone number search bar
```

---

## Step-by-Step Setup & Run Instructions

### 1. Prerequisites
- **Flutter SDK**: `>= 3.0.0`
- **Android SDK**: `minSdkVersion 24`, `targetSdkVersion 34` (Android 14)
- **Java**: JDK 17
- Physical Android device (recommended for testing incoming calls, SIM detection, and phone state) or an Android Emulator with cellular simulated via Extended Controls.

### 2. Fetch Dependencies
Navigate to the project root and run:
```bash
flutter pub get
```

### 3. Connect Android Device
Ensure USB Debugging is turned on in Developer Options on your physical device:
```bash
adb devices
```

### 4. Build and Run
```bash
flutter run
```

### 5. Testing Call Monitoring
1. **Grant Permissions**: On first launch, click **Grant Permissions** to approve Phone, Call Log, and Notification permissions.
2. **First-Time Sync**: Existing calls in your device's call log will automatically be imported into SQLite.
3. **Incoming Call Test**:
   - Make a test call to your phone.
   - Observe the persistent notification in the status bar indicating `Call Logger Active`.
   - Answer or reject the call.
   - The app immediately logs the event and updates the record with finalized duration.
4. **Reboot Test**:
   - Restart the phone.
   - `BootReceiver` automatically restarts `CallMonitorService` without opening the app UI.

---

## Android Manifest Permissions & Android 14 Compliance

The following permissions are configured in `android/app/src/main/AndroidManifest.xml`:
- `READ_CALL_LOG`: Read accurate call duration, timestamps, and call types.
- `READ_PHONE_STATE`: Broadcast receiver for incoming ring/offhook/idle events.
- `READ_PHONE_NUMBERS`: Query device line 1 number via SubscriptionManager.
- `POST_NOTIFICATIONS`: Android 13+ permission for persistent service notification.
- `FOREGROUND_SERVICE` & `FOREGROUND_SERVICE_SPECIAL_USE`: Android 14 requirement for background execution.
- `RECEIVE_BOOT_COMPLETED`: Resume service on system reboot.

### Google Play Store Policy Notice
Google restricts `READ_CALL_LOG` to apps whose core functionality strictly requires it. For internal, enterprise, or personal deployment (direct APK installation), no declaration form is needed. For public Play Store distribution, you must submit a **Permissions Declaration Form** justifying call logging as the primary purpose of the application.

