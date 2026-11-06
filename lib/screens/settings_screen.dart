import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_record_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import 'pin_lock_screen.dart';

/// SettingsScreen provides transparent controls for Call Log Keeper:
/// - Background call monitoring foreground service toggle (MethodChannel)
/// - Re-syncing device call history
/// - Exporting call records to CSV
/// - Clearing local database records
/// - Transparent data & privacy information
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _exportCsv() async {
    final recordProvider = Provider.of<CallRecordProvider>(context, listen: false);
    if (recordProvider.records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No call records available to export')),
      );
      return;
    }

    final success = await ExportService.exportAndShareCsv(recordProvider.records);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export CSV')),
      );
    }
  }

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Backed-Up Records'),
        content: const Text(
          'Are you sure you want to delete all call records from your local backup? This action is permanent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await Provider.of<CallRecordProvider>(context, listen: false).clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All call records cleared from local database')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final recordProvider = Provider.of<CallRecordProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Monitoring Service Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.radar_rounded,
                          color: Color(0xFF2563EB),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Background Call Monitoring',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'When active, Call Log Keeper runs an ongoing foreground service with a visible persistent notification to automatically back up calls as soon as they end.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                  ),
                  const Divider(height: 24),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Enable Foreground Monitoring',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                    ),
                    subtitle: Text(
                      settings.isMonitoringEnabled
                          ? 'Service is running (notification visible)'
                          : 'Service is stopped',
                      style: TextStyle(
                        fontSize: 12,
                        color: settings.isMonitoringEnabled ? const Color(0xFF16A34A) : Colors.grey,
                      ),
                    ),
                    value: settings.isMonitoringEnabled,
                    activeColor: const Color(0xFF2563EB),
                    onChanged: (val) async {
                      await settings.toggleMonitoring(val);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Manual Backup / Sync Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Call Backup & Synchronization',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Manually sync confirmed calls from your phone call log into your local database.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Sync Call History Now'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        final count = await recordProvider.syncHistoricalCallLogs();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Synced $count calls into backup')),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Security & Password Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded, color: Color(0xFF2563EB)),
                  title: const Text('Change 4-Digit Password', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Enter old password then set a new password'),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PinLockScreen(mode: PinScreenMode.change),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Data Management Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_download_outlined, color: Color(0xFF2563EB)),
                  title: const Text('Export Records to CSV'),
                  subtitle: const Text('Share or save your call backup as a spreadsheet'),
                  onTap: _exportCsv,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('Clear Local Database', style: TextStyle(color: Colors.red)),
                  subtitle: Text(
                    '${recordProvider.totalCalls} records stored in call_log_keeper.db',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  onTap: _confirmClearData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // About & Transparency Policy
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 18, color: Color(0xFF475569)),
                    SizedBox(width: 8),
                    Text(
                      'About Android Services',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Android Services provides background utilities and personal call history management. All call records are stored exclusively on your device inside local storage and never shared.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
