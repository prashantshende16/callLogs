import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/call_record.dart';
import '../services/call_log_service.dart';
import '../services/database_helper.dart';
import '../services/native_call_service.dart';

/// CallRecordProvider manages the UI state of call records,
/// applying search filters, type filters, and real-time native event updates.
class CallRecordProvider with ChangeNotifier {
  List<CallRecord> _records = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _callTypeFilter = 'all'; // 'all', 'incoming', 'outgoing', 'missed', 'rejected'
  DateTime? _startDate;
  DateTime? _endDate;

  StreamSubscription<Map<String, dynamic>>? _nativeEventSub;
  StreamSubscription<String>? _dialerSharedSub;

  List<CallRecord> get records => _records;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String get callTypeFilter => _callTypeFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;

  // Statistics
  int get totalCalls => _records.length;
  int get incomingCount => _records.where((r) => r.isIncoming).length;
  int get outgoingCount => _records.where((r) => r.isOutgoing).length;
  int get missedCount => _records.where((r) => r.isMissed).length;
  int get rejectedCount => _records.where((r) => r.isRejected).length;

  int get totalDurationSeconds =>
      _records.fold<int>(0, (sum, item) => sum + item.durationSeconds);

  CallRecordProvider() {
    loadRecords();
  }

  /// Binds to native call state broadcasts so real-time calls update the database immediately
  void startListeningToNativeEvents(String Function() getReceiverNumber) {
    _nativeEventSub?.cancel();
    _nativeEventSub = NativeCallService.callEventStream.listen((event) async {
      final eventType = event['event'] as String?;
      final receiverNumber = getReceiverNumber();

      if (kDebugMode) {
        print('Native call event received in Provider: $event');
      }

      if (eventType == 'ended') {
        final callerNumber = (event['number'] as String?) ?? 'Unknown';
        final callerName = event['callerName'] as String?;
        final callType = (event['callType'] as String?) ?? 'incoming';
        final callStatus = (event['callStatus'] as String?) ?? 'ended';
        final startTime = (event['startTime'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
        final endTime = (event['endTime'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
        final durationSeconds = (event['durationSeconds'] as int?) ?? 0;
        final simSlot = event['simSlot'] as String?;
        final audioPath = event['audioPath'] as String?;

        final record = CallRecord(
          callerNumber: callerNumber,
          callerName: callerName,
          receiverNumber: receiverNumber,
          callType: callType,
          callStatus: callStatus,
          startTime: startTime,
          endTime: endTime,
          durationSeconds: durationSeconds,
          simSlot: simSlot,
          audioPath: audioPath,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        await DatabaseHelper.instance.insert(record);
        await loadRecords();
      } else if (eventType == 'sync_latest_call_log') {
        // Delayed sync to fetch exact duration and system metadata from CallLog
        await CallLogService.syncLatestCall(fallbackReceiverNumber: receiverNumber);
        await loadRecords();
      } else if (eventType == 'native_recording_found') {
        final callerNumber = (event['number'] as String?) ?? '';
        final startTime = (event['startTime'] as int?) ?? 0;
        final audioPath = event['audioPath'] as String?;

        if (audioPath != null && audioPath.isNotEmpty) {
          final updated = await DatabaseHelper.instance.updateAudioPathByNumber(callerNumber, startTime, audioPath);
          if (updated == 0) {
            await DatabaseHelper.instance.updateLatestCallAudioPath(audioPath);
          }
          await loadRecords();
        }
      }
    });

    // Listen to audio shared directly from phone dialer (e.g. Google Phone dialer share button)
    _dialerSharedSub?.cancel();
    _dialerSharedSub = NativeCallService.audioSharedFromDialerStream.listen((audioPath) async {
      if (kDebugMode) {
        print('Audio shared from dialer received in Provider: $audioPath');
      }
      if (audioPath.isNotEmpty) {
        await DatabaseHelper.instance.updateLatestCallAudioPath(audioPath);
        await loadRecords();
      }
    });
  }

  /// Scans Samsung/OEM native call recording directories and links matching audio files to records
  Future<int> scanAndLinkNativeRecordings() async {
    int linkedCount = 0;
    try {
      final unlinked = _records.where((r) => r.audioPath == null || r.audioPath!.isEmpty).toList();
      for (final rec in unlinked) {
        final path = await NativeCallService.findNativeRecordingForCall(
          number: rec.callerNumber,
          startTime: rec.startTime,
          endTime: rec.endTime,
        );
        if (path != null && rec.id != null) {
          await DatabaseHelper.instance.updateAudioPath(rec.id!, path);
          linkedCount++;
        }
      }
      if (linkedCount > 0) {
        await loadRecords();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error scanning native recordings: $e');
      }
    }
    return linkedCount;
  }

  /// Loads records from SQLite with active query and filter criteria
  Future<void> loadRecords() async {
    _isLoading = true;
    notifyListeners();

    try {
      _records = await DatabaseHelper.instance.getAll(
        searchQuery: _searchQuery,
        callTypeFilter: _callTypeFilter,
        startDate: _startDate,
        endDate: _endDate,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error loading records from SQLite: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates search text query and refreshes list
  void setSearchQuery(String query) {
    _searchQuery = query;
    loadRecords();
  }

  /// Updates call type filter ('all', 'incoming', 'outgoing', 'missed', 'rejected')
  void setCallTypeFilter(String type) {
    _callTypeFilter = type;
    loadRecords();
  }

  /// Updates start and end date range filters
  void setDateRange(DateTime? start, DateTime? end) {
    _startDate = start;
    _endDate = end;
    loadRecords();
  }

  /// Clears all active filters (search query, type filter, date range)
  void resetFilters() {
    _searchQuery = '';
    _callTypeFilter = 'all';
    _startDate = null;
    _endDate = null;
    loadRecords();
  }

  /// Imports historical call logs from system CallLog provider
  Future<int> syncHistoricalCallLogs({required String fallbackReceiverNumber}) async {
    _isLoading = true;
    notifyListeners();

    final count = await CallLogService.syncHistoricalCallLogs(
      fallbackReceiverNumber: fallbackReceiverNumber,
    );

    await loadRecords();
    return count;
  }

  /// Deletes a specific call record by ID
  Future<void> deleteRecord(int id) async {
    await DatabaseHelper.instance.delete(id);
    _records.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// Clears all call records from the SQLite database
  Future<void> clearAll() async {
    await DatabaseHelper.instance.clearAll();
    _records.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _nativeEventSub?.cancel();
    _dialerSharedSub?.cancel();
    super.dispose();
  }
}

