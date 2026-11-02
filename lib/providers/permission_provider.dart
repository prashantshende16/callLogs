import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/permission_service.dart';

/// PermissionProvider manages the state and request flows for all runtime permissions.
class PermissionProvider with ChangeNotifier {
  bool _isLoading = true;
  bool _areAllGranted = false;
  bool _isPermanentlyDenied = false;

  Map<Permission, PermissionStatus> _statuses = {};

  bool get isLoading => _isLoading;
  bool get areAllGranted => _areAllGranted;
  bool get isPermanentlyDenied => _isPermanentlyDenied;
  Map<Permission, PermissionStatus> get statuses => _statuses;

  PermissionProvider() {
    checkPermissions();
  }

  /// Checks the current status of all required permissions
  Future<void> checkPermissions() async {
    _isLoading = true;
    notifyListeners();

    try {
      _statuses = await PermissionService.checkStatuses();

      _areAllGranted = _statuses.values.every((s) => s.isGranted);
      _isPermanentlyDenied = _statuses.values.any((s) => s.isPermanentlyDenied);
    } catch (e) {
      if (kDebugMode) {
        print('Error checking permissions: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Triggers a prompt to request any ungranted permissions
  Future<bool> requestPermissions() async {
    _isLoading = true;
    notifyListeners();

    try {
      _statuses = await PermissionService.requestAll();

      _areAllGranted = _statuses.values.every((s) => s.isGranted);
      _isPermanentlyDenied = _statuses.values.any((s) => s.isPermanentlyDenied);

      return _areAllGranted;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting permissions: $e');
      }
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Directs user to the system App Settings if permissions are permanently denied
  Future<void> openSettings() async {
    await PermissionService.openSettings();
  }
}

