import 'package:permission_handler/permission_handler.dart';

/// PermissionService handles checking and requesting standard permissions
/// required for Call Log Keeper (phone state, contacts, notifications).
class PermissionService {
  /// Core permissions required for phone monitoring and contact resolution
  static final List<Permission> corePermissions = [
    Permission.phone, // READ_PHONE_STATE
    Permission.contacts, // READ_CONTACTS
    Permission.notification, // POST_NOTIFICATIONS (Android 13+)
  ];

  /// Media / storage permissions for call recording audio file access
  static final List<Permission> mediaPermissions = [
    Permission.audio, // READ_MEDIA_AUDIO (Android 13+)
    Permission.storage, // READ_EXTERNAL_STORAGE (Android 12-)
  ];

  static List<Permission> get allPermissions => [
    ...corePermissions,
    ...mediaPermissions,
  ];

  /// Checks if core required permissions are currently granted
  static Future<bool> areAllPermissionsGranted() async {
    for (final perm in corePermissions) {
      final status = await perm.status;
      if (!status.isGranted) return false;
    }
    return true;
  }

  /// Detailed permission status map
  static Future<Map<Permission, PermissionStatus>> checkStatuses() async {
    final map = <Permission, PermissionStatus>{};
    for (final perm in allPermissions) {
      try {
        map[perm] = await perm.status;
      } catch (_) {}
    }
    return map;
  }

  /// Requests all permissions and returns updated status map
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    return await allPermissions.request();
  }

  /// Opens the Android system App Settings screen
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
