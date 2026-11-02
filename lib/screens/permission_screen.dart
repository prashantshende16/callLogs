import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

/// PermissionScreen displays a user-friendly explanation of all required
/// permissions on first launch, guiding the user to grant them or open settings.
class PermissionScreen extends StatefulWidget {
  final VoidCallback onPermissionsGranted;

  const PermissionScreen({
    Key? key,
    required this.onPermissionsGranted,
  }) : super(key: key);

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check permissions when returning from system Settings
      final permProvider = Provider.of<PermissionProvider>(context, listen: false);
      permProvider.checkPermissions().then((_) {
        if (permProvider.areAllGranted) {
          widget.onPermissionsGranted();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final permProvider = Provider.of<PermissionProvider>(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Header Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.security_rounded,
                  size: 40,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 20),

              // Title & Subtitle
              const Text(
                'Permissions Required',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'To automatically monitor incoming calls and store accurate call records in your local SQLite database, Call Logger requires the following permissions:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Permission Explanations List
              Expanded(
                child: ListView(
                  children: [
                    _buildPermissionItem(
                      icon: Icons.phone_in_talk,
                      title: 'Phone State & Numbers',
                      description:
                          'Detects when your phone rings, answers, or ends calls, and reads SIM/hardware phone numbers.',
                      isGranted: permProvider.areAllGranted,
                    ),
                    _buildPermissionItem(
                      icon: Icons.history,
                      title: 'Call Log Access',
                      description:
                          'Reads finalized call duration, call types (missed/rejected), and syncs call history.',
                      isGranted: permProvider.areAllGranted,
                    ),
                    _buildPermissionItem(
                      icon: Icons.notifications_active_outlined,
                      title: 'Notifications (Android 13+)',
                      description:
                          'Shows a persistent foreground service notification ensuring 24/7 background call monitoring.',
                      isGranted: permProvider.areAllGranted,
                    ),
                    _buildPermissionItem(
                      icon: Icons.mic_outlined,
                      title: 'Microphone (Voice Recording)',
                      description:
                          'Records call audio directly when a call is connected so you can listen back to conversations.',
                      isGranted: permProvider.areAllGranted,
                    ),
                  ],
                ),
              ),

              // Bottom Actions
              if (permProvider.isPermanentlyDenied) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade800),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Some permissions are permanently denied. Please enable them in App Settings.',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.settings),
                    label: const Text('Open App Settings', style: TextStyle(fontSize: 16)),
                    onPressed: () => permProvider.openSettings(),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: permProvider.isLoading
                        ? null
                        : () async {
                            final granted = await permProvider.requestPermissions();
                            if (granted) {
                              widget.onPermissionsGranted();
                            }
                          },
                    child: permProvider.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Grant Permissions', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isGranted ? Colors.green.shade50 : Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: isGranted ? Colors.green.shade700 : Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    height: 1.3,
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

