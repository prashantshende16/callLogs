import 'package:permission_handler/permission_handler.dart';

/// PermissionService handles requesting, checking, and diagnosing
/// runtime permissions required for call logging and background services.
class PermissionService {
  /// The list of essential permissions required by Call Logger.
  static final List<Permission> requiredPermissions = [
    Permission.phone, // READ_PHONE_STATE, CALL_PHONE
    Permission.contacts, // Optional helper for contact names if needed
    // Permission.phoneState,
    Permission.notification, // POST_NOTIFICATIONS (Android 13+)
  ];

  /// Checks if all crucial permissions are currently granted.
  static Future<bool> areAllPermissionsGranted() async {
    final phoneStatus = await Permission.phone.status;
    final notifStatus = await Permission.notification.status;

    // Direct check for phone permissions
    final phoneOk = phoneStatus.isGranted;
    final notifOk = notifStatus.isGranted;

    return phoneOk && notifOk;
  }

  /// Detailed permission status map
  static Future<Map<Permission, PermissionStatus>> checkStatuses() async {
    return {
      Permission.phone: await Permission.phone.status,
      Permission.notification: await Permission.notification.status,
    };
  }

  /// Requests all permissions and returns the updated status map.
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    final permissions = [
      Permission.phone,
      Permission.notification,
    ];
    return await permissions.request();
  }

  /// Opens the Android system App Settings screen
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}

