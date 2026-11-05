import 'package:permission_handler/permission_handler.dart';

/// PermissionService handles checking and requesting standard permissions
/// required for Call Log Keeper (phone state, contacts, notifications).
class PermissionService {
  /// Crucial permissions required for transparent call history backup
  static final List<Permission> requiredPermissions = [
    Permission.phone, // READ_PHONE_STATE
    Permission.contacts, // READ_CONTACTS
    Permission.notification, // POST_NOTIFICATIONS (Android 13+)
  ];

  /// Checks if all crucial permissions are currently granted
  static Future<bool> areAllPermissionsGranted() async {
    for (final perm in requiredPermissions) {
      final status = await perm.status;
      if (!status.isGranted) return false;
    }
    return true;
  }

  /// Detailed permission status map
  static Future<Map<Permission, PermissionStatus>> checkStatuses() async {
    return {
      Permission.phone: await Permission.phone.status,
      Permission.contacts: await Permission.contacts.status,
      Permission.notification: await Permission.notification.status,
    };
  }

  /// Requests permissions and returns updated status map
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    return await requiredPermissions.request();
  }

  /// Opens the Android system App Settings screen
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
