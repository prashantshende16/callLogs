import 'dart:async';
import 'package:flutter/services.dart';

/// NativeCallService handles platform communication with the Kotlin native layer:
/// - Controlling CallMonitorService (foreground service)
/// - Querying SIM / TelephonyManager device phone number
/// - Receiving real-time call state callbacks from CallStateReceiver
class NativeCallService {
  static const MethodChannel _channel = MethodChannel('com.example.call_logger/monitor');

  static final StreamController<Map<String, dynamic>> _callEventStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of real-time call events from CallStateReceiver
  static Stream<Map<String, dynamic>> get callEventStream => _callEventStreamController.stream;

  static bool _isInitialized = false;

  /// Initializes the MethodCallHandler to listen for Kotlin callbacks
  static void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCallEvent') {
        final arguments = call.arguments;
        if (arguments is Map) {
          final eventData = Map<String, dynamic>.from(arguments);
          _callEventStreamController.add(eventData);
        }
      }
    });
  }

  /// Starts the Android foreground service for 24/7 call monitoring
  static Future<bool> startMonitoring() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('startMonitoring');
      return result ?? false;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NativeCallService.startMonitoring failed: ${e.message}');
      return false;
    }
  }

  /// Stops the Android foreground service
  static Future<bool> stopMonitoring() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('stopMonitoring');
      return result ?? false;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NativeCallService.stopMonitoring failed: ${e.message}');
      return false;
    }
  }

  /// Checks if the foreground service is actively running
  static Future<bool> isMonitoringActive() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('isMonitoringActive');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Retrieves the hardware device phone number from SubscriptionManager or TelephonyManager.
  /// Returns null if restricted by OS, carrier, or SIM card.
  static Future<String?> getDevicePhoneNumber() async {
    try {
      final String? number = await _channel.invokeMethod<String>('getDevicePhoneNumber');
      if (number != null && number.trim().isNotEmpty) {
        return number.trim();
      }
      return null;
    } on PlatformException catch (_) {
      return null;
    }
  }
}

