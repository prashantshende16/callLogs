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

  static final StreamController<void> _audioCompletedController =
      StreamController<void>.broadcast();

  static final StreamController<String> _audioSharedFromDialerController =
      StreamController<String>.broadcast();

  static final StreamController<void> _callLoggedController =
      StreamController<void>.broadcast();

  /// Stream of real-time call events from CallStateReceiver
  static Stream<Map<String, dynamic>> get callEventStream => _callEventStreamController.stream;

  /// Stream notified when CallMonitorService saves a new call record
  static Stream<void> get callLoggedStream => _callLoggedController.stream;

  /// Stream notified when audio finishes playing
  static Stream<void> get audioCompletedStream => _audioCompletedController.stream;

  /// Stream notified when audio file is shared directly from the phone dialer
  static Stream<String> get audioSharedFromDialerStream =>
      _audioSharedFromDialerController.stream;

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
      } else if (call.method == 'onAudioPlaybackCompleted') {
        _audioCompletedController.add(null);
      } else if (call.method == 'onAudioSharedFromDialer') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty) {
          _audioSharedFromDialerController.add(path);
        }
      } else if (call.method == 'onCallLogged') {
        _callLoggedController.add(null);
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

  /// Syncs historical calls from system CallLog into local database
  static Future<int> syncHistoricalCalls() async {
    try {
      final int? count = await _channel.invokeMethod<int>('syncHistoricalCalls');
      return count ?? 0;
    } catch (_) {
      return 0;
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

  /// Plays a recorded voice call audio file. Returns total duration in milliseconds.
  static Future<int> playAudio(String path) async {
    try {
      final int? duration = await _channel.invokeMethod<int>('playAudio', {'path': path});
      return duration ?? 0;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('playAudio error: ${e.message}');
      return 0;
    }
  }

  /// Pauses active audio playback
  static Future<bool> pauseAudio() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('pauseAudio');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Resumes paused audio playback
  static Future<bool> resumeAudio() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('resumeAudio');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Stops audio playback
  static Future<bool> stopAudio() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('stopAudio');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Seeks to a specific millisecond position in the active audio file
  static Future<bool> seekAudio(int positionMs) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('seekAudio', {'position': positionMs});
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Gets audio duration in milliseconds
  static Future<int> getAudioDuration(String path) async {
    try {
      final int? duration = await _channel.invokeMethod<int>('getAudioDuration', {'path': path});
      return duration ?? 0;
    } on PlatformException catch (_) {
      return 0;
    }
  }

  /// Searches for a native Samsung/OEM phone call recording matching a specific call record
  static Future<String?> findNativeRecordingForCall({
    required String number,
    required int startTime,
    required int endTime,
  }) async {
    try {
      final String? path = await _channel.invokeMethod<String>(
        'findNativeRecordingForCall',
        {
          'number': number,
          'startTime': startTime,
          'endTime': endTime,
        },
      );
      return path;
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Scans all native Samsung/OEM call recordings available in storage
  static Future<List<Map<String, dynamic>>> scanAllNativeRecordings() async {
    try {
      final List<dynamic>? list = await _channel.invokeMethod<List<dynamic>>('scanAllNativeRecordings');
      if (list != null) {
        return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
      return [];
    } on PlatformException catch (_) {
      return [];
    }
  }

  /// Copies an audio file (.wav, .m4a, .mp3) into app backup storage
  static Future<String?> copyAudioToAppStorage(String sourcePath, String number) async {
    try {
      final String? copiedPath = await _channel.invokeMethod<String>(
        'copyAudioToAppStorage',
        {
          'path': sourcePath,
          'number': number,
        },
      );
      return copiedPath;
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Checks if All Files Access (MANAGE_EXTERNAL_STORAGE) is granted on Android 11+
  static Future<bool> checkAllFilesAccess() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('checkAllFilesAccess');
      return result ?? true;
    } on PlatformException catch (_) {
      return true;
    }
  }

  /// Opens the system All Files Access settings page for this app
  static Future<bool> openAllFilesAccessSettings() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('openAllFilesAccessSettings');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Opens the system Android file picker to allow selecting any .wav, .mp3, or .m4a file
  static Future<String?> pickAudioWithSystemPicker() async {
    try {
      final String? path = await _channel.invokeMethod<String>('pickAudioWithSystemPicker');
      return path;
    } on PlatformException catch (_) {
      return null;
    }
  }
}

