import 'package:call_log/call_log.dart';
import '../models/call_record.dart';
import 'database_helper.dart';

/// CallLogService interfaces with the device's system CallLog content provider
/// to extract accurate call duration, timestamps, numbers, and types.
class CallLogService {
  /// Maps CallLog package CallType enum to integer type
  static int mapCallTypeToInt(CallType? type) {
    if (type == null) return 1;
    switch (type) {
      case CallType.incoming:
        return 1;
      case CallType.outgoing:
        return 2;
      case CallType.missed:
        return 3;
      case CallType.rejected:
      case CallType.blocked:
        return 5;
      default:
        return 1;
    }
  }

  /// Maps CallLog entry to CallRecord model
  static CallRecord entryToCallRecord(CallLogEntry entry, [String? fallbackReceiverNumber]) {
    final callerNum = entry.number?.trim().isNotEmpty == true ? entry.number!.trim() : 'Unknown';
    final callerName = (entry.name != null && entry.name!.trim().isNotEmpty) ? entry.name!.trim() : null;
    final startTime = entry.timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final durationSec = entry.duration ?? 0;
    final typeInt = mapCallTypeToInt(entry.callType);

    return CallRecord(
      number: callerNum,
      name: callerName,
      type: typeInt,
      date: startTime,
      duration: durationSec,
    );
  }

  /// One-time sync to import all historical device call records into the SQLite database.
  /// Ignores existing records due to unique constraint.
  static Future<int> syncHistoricalCallLogs({String? fallbackReceiverNumber}) async {
    try {
      final Iterable<CallLogEntry> entries = await CallLog.get();
      final records = <CallRecord>[];

      for (final entry in entries) {
        records.add(entryToCallRecord(entry, fallbackReceiverNumber));
      }

      if (records.isNotEmpty) {
        return await DatabaseHelper.instance.insertBatch(records);
      }
      return 0;
    } catch (e) {
      // ignore: avoid_print
      print('Error syncing historical call logs: $e');
      return 0;
    }
  }

  /// Fetches and saves the latest completed call from system call log.
  static Future<CallRecord?> syncLatestCall({String? fallbackReceiverNumber}) async {
    try {
      final now = DateTime.now();
      final queryStartTime = now.subtract(const Duration(minutes: 15)).millisecondsSinceEpoch;

      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: queryStartTime,
      );

      final list = entries.toList();
      if (list.isEmpty) return null;

      list.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      final latest = list.first;

      final record = entryToCallRecord(latest, fallbackReceiverNumber);
      await DatabaseHelper.instance.insert(record);
      return record;
    } catch (e) {
      // ignore: avoid_print
      print('Error syncing latest call: $e');
      return null;
    }
  }
}
