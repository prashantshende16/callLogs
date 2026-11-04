import 'package:permission_handler/permission_handler.dart';

/// PermissionService handles requesting, checking, and diagnosing
/// runtime permissions required for call logging and background services.
class PermissionService {
  /// The list of essential permissions required by Call Logger.
  static final List<Permission> requiredPermissions = [
    Permission.phone, // READ_PHONE_STATE, CALL_PHONE
    Permission.notification, // POST_NOTIFICATIONS (Android 13+)
    Permission.microphone, // RECORD_AUDIO for voice call recording
    Permission.manageExternalStorage, // All files access to read/copy Vivo & Realme recordings
  ];

  /// Checks if all crucial permissions are currently granted.
  static Future<bool> areAllPermissionsGranted() async {
    final phoneStatus = await Permission.phone.status;
    final notifStatus = await Permission.notification.status;
    final micStatus = await Permission.microphone.status;

    return phoneStatus.isGranted && notifStatus.isGranted && micStatus.isGranted;
  }

  /// Detailed permission status map
  static Future<Map<Permission, PermissionStatus>> checkStatuses() async {
    return {
      Permission.phone: await Permission.phone.status,
      Permission.contacts: await Permission.contacts.status,
      Permission.notification: await Permission.notification.status,
      Permission.microphone: await Permission.microphone.status,
      Permission.manageExternalStorage: await Permission.manageExternalStorage.status,
    };
  }

  /// Requests all permissions and returns the updated status map.
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    final permissions = [
      Permission.phone,
      Permission.contacts,
      Permission.notification,
      Permission.microphone,
      Permission.manageExternalStorage,
    ];
    return await permissions.request();
  }

  /// Opens the Android system App Settings screen
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}

