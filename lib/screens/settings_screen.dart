import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_record_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';

/// SettingsScreen provides configuration for:
/// - Monitoring toggle (starts/stops native foreground service)
/// - Setting manual or auto-detected device receiver phone number
/// - Re-syncing device call history
/// - Exporting call records to CSV
/// - Purging database records
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _phoneController;
  bool _isSavingPhone = false;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _phoneController = TextEditingController(text: settings.userPhoneNumber);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _savePhoneNumber() async {
    setState(() => _isSavingPhone = true);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await settings.setUserPhoneNumber(_phoneController.text.trim());
    setState(() => _isSavingPhone = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receiver phone number updated')),
      );
    }
  }

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
        title: const Text('Clear All Call Records'),
        content: const Text(
          'Are you sure you want to delete all logged call records? This action is permanent and cannot be undone.',
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
          const SnackBar(content: Text('All call records cleared from SQLite')),
        );
      }
    }
  }

  Future<void> _syncCallLogs() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final recordProvider = Provider.of<CallRecordProvider>(context, listen: false);

    final count = await recordProvider.syncHistoricalCallLogs(
      fallbackReceiverNumber: settings.effectivePhoneNumber,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $count historical call records')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final recordProvider = Provider.of<CallRecordProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          // Monitoring Section
          _buildSectionHeader('Monitoring Service'),
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Automatic Call Monitoring',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    settings.isMonitoringEnabled
                        ? 'Active foreground service (Android 14+ specialUse)'
                        : 'Monitoring stopped (calls will not be recorded)',
                    style: TextStyle(
                      color: settings.isMonitoringEnabled ? Colors.green.shade700 : Colors.red.shade700,
                      fontSize: 12.5,
                    ),
                  ),
                  value: settings.isMonitoringEnabled,
                  onChanged: (val) => settings.toggleMonitoring(val),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    'Keeps a persistent notification running to guarantee 24/7 background detection across device reboots and app termination.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Voice Call Recording Options
          _buildSectionHeader('Voice Call Recording'),
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Auto Speakerphone on Call',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Switches call to loudspeaker so microphone captures both sides clearly',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  value: settings.autoSpeakerphone,
                  onChanged: (val) => settings.toggleAutoSpeakerphone(val),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    'On Android 10+, phone calls record through the microphone. Turning on speakerphone ensures the caller voice is loud enough to be clearly recorded.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Samsung / Native Dialer Call Recording (3-dots option)
          _buildSectionHeader('Samsung Native 3-Dot Recording (Option 1)'),
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Samsung Native Hardware Recorder',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '1. Open Samsung Phone App\n'
                        '2. Tap 3-dots (top right) → Settings\n'
                        '3. Tap "Record calls" → Enable "Auto record calls"\n\n'
                        'Samsung records 2-way audio directly into /Recordings/Call/. Call Logger will automatically link these files to your SQLite call records!',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.audio_file_outlined, color: Colors.purple),
                  title: const Text('Scan & Link Native Audio Files'),
                  subtitle: const Text('Matches /Recordings/Call/ files with logged calls'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () async {
                    final linked = await recordProvider.scanAndLinkNativeRecordings();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Linked $linked native recording audio files')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Receiver Number Configuration
          _buildSectionHeader('Device (Receiver) Phone Number'),
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detected Hardware Number: ${settings.detectedPhoneNumber ?? "Not reported by SIM card"}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: settings.detectedPhoneNumber != null ? Colors.black87 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'My Phone Number (Receiver)',
                      hintText: '+1 555 123 4567',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Re-detect SIM Number',
                        onPressed: () => settings.detectDevicePhoneNumber(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Note: Android and SIM carriers frequently block reading line 1 number for privacy. Setting your number manually ensures the receiver column accurately identifies this device.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSavingPhone ? null : _savePhoneNumber,
                      child: _isSavingPhone
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save Number'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Data Management Section
          _buildSectionHeader('Data Management'),
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync, color: Colors.blue),
                  title: const Text('Sync System Call History'),
                  subtitle: const Text('Imports existing call records from device call log'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _syncCallLogs,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download, color: Colors.green),
                  title: const Text('Export Records to CSV'),
                  subtitle: Text('${recordProvider.totalCalls} records stored in SQLite'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _exportCsv,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    'Clear All Database Records',
                    style: TextStyle(color: Colors.red),
                  ),
                  subtitle: const Text('Permanently purges call_records SQLite table'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _confirmClearData,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // About Section
          _buildSectionHeader('About Call Logger'),
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Call Logger v1.0.0 (Android Only)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Stores caller and receiver numbers in local SQLite database (sqflite).\n'
                    'Includes BroadcastReceiver for android.intent.action.PHONE_STATE, BOOT_COMPLETED auto-restart, and system call log reconciliation.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }
}

