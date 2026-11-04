import 'package:call_log/call_log.dart';
import '../models/call_record.dart';
import 'database_helper.dart';

/// CallLogService interfaces with the device's system CallLog content provider
/// to extract accurate call duration, timestamps, numbers, and types.
class CallLogService {
  /// Maps CallLog package CallType enum to standardized lowercase string
  static String mapCallType(CallType? type) {
    if (type == null) return 'incoming';
    switch (type) {
      case CallType.incoming:
        return 'incoming';
      case CallType.outgoing:
        return 'outgoing';
      case CallType.missed:
        return 'missed';
      case CallType.rejected:
      case CallType.blocked:
        return 'rejected';
      default:
        return 'incoming';
    }
  }

  /// Maps CallLog entry to CallRecord model
  static CallRecord entryToCallRecord(CallLogEntry entry, String fallbackReceiverNumber) {
    final callerNum = entry.number?.trim().isNotEmpty == true ? entry.number!.trim() : 'Unknown';
    final callerName = (entry.name != null && entry.name!.trim().isNotEmpty) ? entry.name!.trim() : null;
    final startTime = entry.timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final durationSec = entry.duration ?? 0;
    final endTime = startTime + (durationSec * 1000);
    final callType = mapCallType(entry.callType);
    final callStatus = (callType == 'missed' || callType == 'rejected') ? 'missed' : 'ended';

    String? simSlot;
    if (entry.simDisplayName != null && entry.simDisplayName!.isNotEmpty) {
      simSlot = entry.simDisplayName;
    } else if (entry.phoneAccountId != null && entry.phoneAccountId!.isNotEmpty) {
      simSlot = 'SIM ${entry.phoneAccountId}';
    }

    return CallRecord(
      callerNumber: callerNum,
      callerName: callerName,
      receiverNumber: fallbackReceiverNumber,
      callType: callType,
      callStatus: callStatus,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: durationSec,
      simSlot: simSlot,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// One-time sync to import all historical device call records into the SQLite database.
  /// Ignores existing records due to unique constraint.
  static Future<int> syncHistoricalCallLogs({required String fallbackReceiverNumber}) async {
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
  /// Typically called 1-2 seconds after a call ends to get finalized duration and carrier details.
  static Future<CallRecord?> syncLatestCall({required String fallbackReceiverNumber}) async {
    try {
      final now = DateTime.now();
      // Look back 15 minutes to guarantee finding the call that just ended
      final queryStartTime = now.subtract(const Duration(minutes: 15)).millisecondsSinceEpoch;

      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: queryStartTime,
      );

      final list = entries.toList();
      if (list.isEmpty) return null;

      // Sort by timestamp descending
      list.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      final latest = list.first;

      final record = entryToCallRecord(latest, fallbackReceiverNumber);
      final insertedId = await DatabaseHelper.instance.insert(record);

      if (insertedId > 0) {
        return record.copyWith(id: insertedId);
      }
      return record;
    } catch (e) {
      // ignore: avoid_print
      print('Error querying latest call log: $e');
      return null;
    }
  }
}

