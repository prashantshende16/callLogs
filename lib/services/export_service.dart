import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/call_record.dart';

/// ExportService creates CSV files from CallRecord lists and shares them.
class ExportService {
  /// Converts records into CSV text and opens the system Share sheet
  static Future<bool> exportAndShareCsv(List<CallRecord> records) async {
    try {
      final rows = <List<dynamic>>[];

      // Header row
      rows.add([
        'ID',
        'Caller Number',
        'Receiver Number',
        'Call Type',
        'Call Status',
        'Start Time (Epoch ms)',
        'Start Time (Formatted)',
        'End Time (Epoch ms)',
        'Duration (Seconds)',
        'Duration (Formatted)',
        'SIM Slot',
        'Logged At (Formatted)',
      ]);

      // Data rows
      for (final r in records) {
        final startDt = r.startTime > 0
            ? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(r.startTime))
            : '';
        final loggedDt = r.createdAt > 0
            ? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(r.createdAt))
            : '';

        rows.add([
          r.id ?? '',
          r.callerNumber,
          r.receiverNumber,
          r.callType,
          r.callStatus,
          r.startTime,
          startDt,
          r.endTime,
          r.durationSeconds,
          r.formattedDuration,
          r.simSlot ?? 'N/A',
          loggedDt,
        ]);
      }

      final csvContent = const ListToCsvConverter().convert(rows);

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${tempDir.path}/call_records_$timestamp.csv';
      final file = File(filePath);

      await file.writeAsString(csvContent);

      final xFile = XFile(filePath, mimeType: 'text/csv');
      final result = await Share.shareXFiles(
        [xFile],
        text: 'Exported Call Records (${records.length} items)',
        subject: 'Call Logger Export - $timestamp',
      );

      return result.status == ShareResultStatus.success || result.status == ShareResultStatus.dismissed;
    } catch (e) {
      // ignore: avoid_print
      print('ExportService error: $e');
      return false;
    }
  }
}

