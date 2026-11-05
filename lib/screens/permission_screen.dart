import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

/// PermissionScreen displays a transparent, user-friendly explanation of all
/// permissions required by Call Log Keeper to back up personal call history.
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // App Brand Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.history_edu_rounded,
                      size: 32,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Call Log Keeper',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Transparent Personal Call Backup',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              const Text(
                'Permissions & Transparency',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'To automatically back up your call records in the background and display contact names, Call Log Keeper requests the following standard Android permissions:',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF475569),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Permissions List
              Expanded(
                child: ListView(
                  children: [
                    _buildPermissionItem(
                      icon: Icons.call_rounded,
                      title: 'Call Logs (READ_CALL_LOG)',
                      description:
                          'Reads your confirmed incoming, outgoing, and missed call history to create your local backup.',
                      isGranted: permProvider.isCallLogGranted,
                    ),
                    const SizedBox(height: 12),
                    _buildPermissionItem(
                      icon: Icons.phone_in_talk_rounded,
                      title: 'Phone State (READ_PHONE_STATE)',
                      description:
                          'Detects when a phone call terminates so Call Log Keeper can sync the newly completed call.',
                      isGranted: permProvider.isPhoneGranted,
                    ),
                    const SizedBox(height: 12),
                    _buildPermissionItem(
                      icon: Icons.contacts_rounded,
                      title: 'Contacts (READ_CONTACTS)',
                      description:
                          'Resolves contact names for phone numbers so you see familiar names in your backup.',
                      isGranted: permProvider.isContactsGranted,
                    ),
                    const SizedBox(height: 12),
                    _buildPermissionItem(
                      icon: Icons.notifications_active_rounded,
                      title: 'Visible Notifications (POST_NOTIFICATIONS)',
                      description:
                          'Displays the persistent, visible ongoing notification required by Android while monitoring is active.',
                      isGranted: permProvider.isNotificationGranted,
                    ),
                    const SizedBox(height: 16),

                    // Privacy notice box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, size: 20, color: Color(0xFF2563EB)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '100% Local Storage: All call records are saved strictly on this device in call_log_keeper.db. No data is ever sent to any server.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF334155),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Action Button
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    await permProvider.requestAllPermissions();
                    if (permProvider.areAllGranted) {
                      widget.onPermissionsGranted();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Grant Permissions & Start Backup',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 10),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isGranted ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGranted ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isGranted ? const Color(0xFF22C55E).withValues(alpha: 0.15) : const Color(0xFF64748B).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGranted ? Icons.check_circle_rounded : icon,
              size: 20,
              color: isGranted ? const Color(0xFF16A34A) : const Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: isGranted ? const Color(0xFF15803D) : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
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
