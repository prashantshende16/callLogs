import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/native_call_service.dart';

/// SettingsProvider manages user preferences, device phone number detection,
/// and background monitoring service state.
class SettingsProvider with ChangeNotifier {
  static const String _keyMonitoring = 'is_monitoring_enabled';
  static const String _keyUserPhone = 'user_phone_number';
  static const String _keyInitialSyncDone = 'has_synced_initial_call_log';
  static const String _keyAutoSpeakerphone = 'auto_speakerphone_recording';

  bool _isMonitoringEnabled = true;
  bool _autoSpeakerphone = true;
  String _userPhoneNumber = '';
  String? _detectedPhoneNumber;
  bool _hasInitialSyncDone = false;
  bool _isInitialized = false;

  bool get isMonitoringEnabled => _isMonitoringEnabled;
  bool get autoSpeakerphone => _autoSpeakerphone;
  String get userPhoneNumber => _userPhoneNumber;
  String? get detectedPhoneNumber => _detectedPhoneNumber;
  bool get hasInitialSyncDone => _hasInitialSyncDone;
  bool get isInitialized => _isInitialized;

  /// Effective receiver number: user-specified number takes priority;
  /// falls back to hardware detected number; falls back to 'My Device'.
  String get effectivePhoneNumber {
    if (_userPhoneNumber.trim().isNotEmpty) {
      return _userPhoneNumber.trim();
    }
    if (_detectedPhoneNumber != null && _detectedPhoneNumber!.trim().isNotEmpty) {
      return _detectedPhoneNumber!.trim();
    }
    return 'My Device';
  }

  SettingsProvider() {
    initSettings();
  }

  Future<void> initSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isMonitoringEnabled = prefs.getBool(_keyMonitoring) ?? true;
    _autoSpeakerphone = prefs.getBool(_keyAutoSpeakerphone) ?? true;
    _userPhoneNumber = prefs.getString(_keyUserPhone) ?? '';
    _hasInitialSyncDone = prefs.getBool(_keyInitialSyncDone) ?? false;

    // Detect hardware SIM phone number
    await detectDevicePhoneNumber();

    // Ensure background service matches preference
    if (_isMonitoringEnabled) {
      final active = await NativeCallService.isMonitoringActive();
      if (!active) {
        await NativeCallService.startMonitoring();
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Queries the hardware SubscriptionManager / TelephonyManager for line 1 number
  Future<void> detectDevicePhoneNumber() async {
    try {
      final detected = await NativeCallService.getDevicePhoneNumber();
      if (detected != null && detected.trim().isNotEmpty) {
        _detectedPhoneNumber = detected.trim();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error detecting device phone number: $e');
      }
    }
  }

  /// Sets the user-defined phone number in local preferences
  Future<void> setUserPhoneNumber(String number) async {
    _userPhoneNumber = number.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserPhone, _userPhoneNumber);
    notifyListeners();
  }

  /// Toggles foreground service monitoring on or off
  Future<void> toggleMonitoring(bool enable) async {
    _isMonitoringEnabled = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMonitoring, enable);

    if (enable) {
      await NativeCallService.startMonitoring();
    } else {
      await NativeCallService.stopMonitoring();
    }
    notifyListeners();
  }

  /// Toggles automatic speakerphone activation during call recording
  Future<void> toggleAutoSpeakerphone(bool enable) async {
    _autoSpeakerphone = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSpeakerphone, enable);
    notifyListeners();
  }

  /// Marks the one-time initial call log sync as complete
  Future<void> markInitialSyncDone() async {
    _hasInitialSyncDone = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInitialSyncDone, true);
    notifyListeners();
  }
}

