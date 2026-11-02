import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/call_record_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import '../services/native_call_service.dart';
import 'pin_lock_screen.dart';

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

  void _openChangePassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PinLockScreen(mode: PinScreenMode.change),
      ),
    );
  }

  void _openResetPasswordDialog() {
    final resetController = TextEditingController();
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset, color: Color(0xFF1E3A8A)),
                  SizedBox(width: 8),
                  Text('Reset Password'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the 4-digit Master Reset Code to reset your app password:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    style: const TextStyle(
                      fontSize: 22,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '••••',
                      errorText: dialogError,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final enteredCode = resetController.text.trim();
                    final auth = Provider.of<AuthProvider>(context, listen: false);

                    if (auth.verifyMasterCode(enteredCode)) {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PinLockScreen(mode: PinScreenMode.setup),
                        ),
                      );
                    } else {
                      setDialogState(() {
                        dialogError = 'Invalid Master Code (9876)';
                      });
                    }
                  },
                  child: const Text('Verify & Reset'),
                ),
              ],
            );
          },
        );
      },
    );
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

          // Vivo / Realme / Samsung Native Call Recording
          _buildSectionHeader('Native Call Recording Backup (Vivo, Realme, Samsung)'),
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
                        'Automatic Voice Recording Backup',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '• Vivo: Auto-records calls into /Record/Call/.\n'
                        '• Realme: Records when tapping 3-dots/Record button, saved into /Recordings/Call Recordings/.\n'
                        '• Samsung: Records into /Recordings/Call/.\n\n'
                        'When any call ends, Call Logger immediately finds the newly created recording file, makes an independent backup copy into our app storage, and links it to the call record.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.audio_file_outlined, color: Colors.purple),
                  title: const Text('Scan & Backup Native Audio Files'),
                  subtitle: const Text('Finds device recordings (.wav, .m4a, .mp3) and copies them into app backup'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () async {
                    final linked = await recordProvider.scanAndLinkNativeRecordings();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Backed up and linked $linked native recording files')),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_shared_outlined, color: Colors.indigo),
                  title: const Text('All Files Access Permission'),
                  subtitle: const Text('Grant in phone settings if .wav files are in protected folders'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () async {
                    await NativeCallService.openAllFilesAccessSettings();
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

          // Security & Passcode Section
          _buildSectionHeader('Security & Passcode'),
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined, color: Color(0xFF1E3A8A)),
                  title: const Text('App Access Password'),
                  subtitle: const Text('Secured with 4-digit PIN lock'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.password, color: Color(0xFF3B82F6)),
                  title: const Text('Change Password'),
                  subtitle: const Text('Update your 4-digit access PIN'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _openChangePassword,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_reset, color: Colors.orange),
                  title: const Text('Reset Password'),
                  subtitle: const Text('Reset using Master Code: 9876'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _openResetPasswordDialog,
                ),
              ],
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
          _buildSectionHeader('About Android Services'),
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
                    'Android Services v1.0.0 (Android Only)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Monitors call activities, manages voice recording backups, and provides PIN protected access.\n'
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

