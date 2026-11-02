import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/call_record.dart';
import '../providers/call_record_provider.dart';
import '../widgets/call_type_badge.dart';

/// CallDetailScreen displays comprehensive technical and metadata details for a logged call record.
class CallDetailScreen extends StatelessWidget {
  final CallRecord record;

  const CallDetailScreen({
    Key? key,
    required this.record,
  }) : super(key: key);

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Call Record'),
        content: Text('Are you sure you want to permanently delete the record for ${record.callerNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && record.id != null) {
      if (context.mounted) {
        await Provider.of<CallRecordProvider>(context, listen: false).deleteRecord(record.id!);
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Call record deleted')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, MMMM dd, yyyy  hh:mm:ss a');

    final startString = record.startTime > 0
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(record.startTime))
        : 'N/A';
    final endString = record.endTime > 0
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(record.endTime))
        : 'N/A';
    final createdString = record.createdAt > 0
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(record.createdAt))
        : 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Details'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete Record',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Header Card: Caller & Type
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    CallTypeBadge(callType: record.callType, showLabel: false),
                    const SizedBox(height: 12),
                    Text(
                      record.callerNumber,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CallTypeBadge(callType: record.callType),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy Number',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _copyToClipboard(context, record.callerNumber, 'Caller number'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Metadata Card
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    _buildDetailRow(
                      icon: Icons.person_outline,
                      label: 'Caller (Sender)',
                      value: record.callerNumber,
                      onCopy: () => _copyToClipboard(context, record.callerNumber, 'Caller number'),
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.phone_android,
                      label: 'Receiver (This Device)',
                      value: record.receiverNumber,
                      onCopy: () => _copyToClipboard(context, record.receiverNumber, 'Receiver number'),
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.info_outline,
                      label: 'Call Status',
                      value: record.callStatus.toUpperCase(),
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.timer_outlined,
                      label: 'Call Duration',
                      value: '${record.formattedDuration} (${record.durationSeconds} seconds)',
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.sim_card_outlined,
                      label: 'SIM Slot / Carrier',
                      value: record.simSlot ?? 'Default SIM',
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.play_arrow_outlined,
                      label: 'Call Started',
                      value: startString,
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.stop_outlined,
                      label: 'Call Ended',
                      value: endString,
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.storage_outlined,
                      label: 'Logged in SQLite',
                      value: createdString,
                    ),
                    if (record.id != null) ...[
                      const Divider(height: 1),
                      _buildDetailRow(
                        icon: Icons.tag,
                        label: 'Database ID',
                        value: '#${record.id}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}

