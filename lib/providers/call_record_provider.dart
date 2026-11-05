import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/call_record.dart';
import '../services/call_log_service.dart';
import '../services/database_helper.dart';
import '../services/native_call_service.dart';

/// CallRecordProvider manages the UI state of call records in Call Log Keeper,
/// applying search filters, type filters, and real-time native event updates.
class CallRecordProvider with ChangeNotifier {
  List<CallRecord> _records = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _callTypeFilter = 'all'; // 'all', 'incoming', 'outgoing', 'missed', 'rejected'
  DateTime? _startDate;
  DateTime? _endDate;

  StreamSubscription<void>? _callLoggedSub;
  StreamSubscription<Map<String, dynamic>>? _nativeEventSub;

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
      _records.fold<int>(0, (sum, item) => sum + item.duration);

  CallRecordProvider() {
    loadRecords();
    _initListeners();
  }

  void _initListeners() {
    _callLoggedSub?.cancel();
    _callLoggedSub = NativeCallService.callLoggedStream.listen((_) {
      if (kDebugMode) {
        print('CallLogKeeper: New call logged notification received. Refreshing list.');
      }
      loadRecords();
    });

    _nativeEventSub?.cancel();
    _nativeEventSub = NativeCallService.callEventStream.listen((event) {
      if (event['event'] == 'ended' || event['event'] == 'sync_latest_call_log') {
        loadRecords();
      }
    });
  }

  /// Compatibility listener hook
  void startListeningToNativeEvents([dynamic getReceiverNumber]) {
    _initListeners();
  }

  /// Syncs all existing calls from system CallLog into local backup
  Future<int> syncHistoricalCallLogs({String? fallbackReceiverNumber}) async {
    _isLoading = true;
    notifyListeners();
    try {
      var count = await NativeCallService.syncHistoricalCalls();
      if (count == 0) {
        count = await CallLogService.syncHistoricalCallLogs(
          fallbackReceiverNumber: fallbackReceiverNumber,
        );
      }
      await loadRecords();
      return count;
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing historical calls: $e');
      }
      return 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  /// Clears active filters
  void resetFilters() {
    _callTypeFilter = 'all';
    _startDate = null;
    _endDate = null;
    loadRecords();
  }

  Future<int> scanAndLinkNativeRecordings() async => 0;

  /// Deletes a specific call record
  Future<void> deleteRecord(int id) async {
    await DatabaseHelper.instance.delete(id);
    await loadRecords();
  }

  /// Clears all call records from database
  Future<void> clearAll() async {
    await DatabaseHelper.instance.clearAll();
    await loadRecords();
  }

  @override
  void dispose() {
    _callLoggedSub?.cancel();
    _nativeEventSub?.cancel();
    super.dispose();
  }
}
