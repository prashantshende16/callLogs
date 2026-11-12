import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/call_record_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/call_record_tile.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/search_bar_widget.dart';
import '../services/native_call_service.dart';
import 'settings_screen.dart';

/// HomeScreen renders the transparent call records list, stats bar, search & filter controls.
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _hasAllFilesAccess = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllFilesAccess();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final recordProvider = Provider.of<CallRecordProvider>(context, listen: false);

      recordProvider.loadRecords();
      recordProvider.startListeningToNativeEvents();

      // Trigger one-time initial sync from device call log if not done yet
      if (!settings.hasInitialSyncDone) {
        recordProvider.syncHistoricalCallLogs().then((_) => settings.markInitialSyncDone());
      }
    });
  }

  Future<void> _checkAllFilesAccess() async {
    final hasAccess = await NativeCallService.checkAllFilesAccess();
    if (mounted && hasAccess != _hasAllFilesAccess) {
      setState(() {
        _hasAllFilesAccess = hasAccess;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllFilesAccess();
      NativeCallService.attachRecordingsToUnattachedCalls();
      // Refresh call records from SQLite as soon as user returns to the app
      Provider.of<CallRecordProvider>(context, listen: false).loadRecords();
    }
  }

  void _showFilterModal() {
    final recordProvider = Provider.of<CallRecordProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterSheet(
        currentType: recordProvider.callTypeFilter,
        currentStartDate: recordProvider.startDate,
        currentEndDate: recordProvider.endDate,
        onApply: (type, start, end) {
          recordProvider.setCallTypeFilter(type);
          recordProvider.setDateRange(start, end);
        },
        onReset: () {
          recordProvider.resetFilters();
        },
      ),
    );
  }

  bool _hasActiveFilters(CallRecordProvider provider) {
    return provider.callTypeFilter != 'all' ||
        provider.startDate != null ||
        provider.endDate != null;
  }

  @override
  Widget build(BuildContext context) {
    final recordProvider = Provider.of<CallRecordProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final hasFilters = _hasActiveFilters(recordProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Android Services',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: settings.isMonitoringEnabled
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: settings.isMonitoringEnabled
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: settings.isMonitoringEnabled
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    settings.isMonitoringEnabled ? 'Active' : 'Paused',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: settings.isMonitoringEnabled
                          ? const Color(0xFF15803D)
                          : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        elevation: 0.5,
        actions: [
          // Filter Button with Badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.filter_list, size: 21),
                tooltip: 'Filter Records',
                onPressed: _showFilterModal,
              ),
              if (hasFilters)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.sync_rounded, size: 21),
            tooltip: 'Sync Device Calls',
            onPressed: () async {
              final count = await recordProvider.syncHistoricalCallLogs();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Synced $count calls from device log')),
                );
              }
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.settings_outlined, size: 21),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          SearchBarWidget(
            initialValue: recordProvider.searchQuery,
            onChanged: (val) => recordProvider.setSearchQuery(val),
            onClear: () => recordProvider.setSearchQuery(''),
          ),

          // Active Filters Chip Row
          if (hasFilters) _buildActiveFilterBar(recordProvider),

          // Summary Stats Bar
          _buildStatsBar(recordProvider),

          // All Files Access Banner for Call Recording Auto-Detection
          if (!_hasAllFilesAccess)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic_rounded, color: Color(0xFF2563EB), size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Call Recording Auto-Save',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Grant storage access to auto-detect and save voice recordings from dialer.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      await NativeCallService.openAllFilesAccessSettings();
                    },
                    child: const Text('Allow', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          // Records List with Pull-to-refresh
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await NativeCallService.attachRecordingsToUnattachedCalls();
                await recordProvider.loadRecords();
                await _checkAllFilesAccess();
              },
              child: recordProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : recordProvider.records.isEmpty
                      ? _buildEmptyState(context, recordProvider)
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: recordProvider.records.length,
                          itemBuilder: (context, index) {
                            final record = recordProvider.records[index];
                            return CallRecordTile(
                              record: record,
                              onDelete: () {
                                if (record.id != null) {
                                  recordProvider.deleteRecord(record.id!);
                                }
                              },
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterBar(CallRecordProvider provider) {
    final dateFormat = DateFormat('MM/dd/yy');
    final chips = <Widget>[];

    if (provider.callTypeFilter != 'all') {
      chips.add(
        Chip(
          label: Text('Type: ${provider.callTypeFilter.toUpperCase()}'),
          deleteIcon: const Icon(Icons.close, size: 14),
          onDeleted: () => provider.setCallTypeFilter('all'),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    if (provider.startDate != null || provider.endDate != null) {
      final startStr = provider.startDate != null ? dateFormat.format(provider.startDate!) : 'Start';
      final endStr = provider.endDate != null ? dateFormat.format(provider.endDate!) : 'End';
      chips.add(
        Chip(
          label: Text('Date: $startStr - $endStr'),
          deleteIcon: const Icon(Icons.close, size: 14),
          onDeleted: () => provider.setDateRange(null, null),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        children: chips,
      ),
    );
  }

  Widget _buildStatsBar(CallRecordProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(child: _buildStatItem('Total', '${provider.totalCalls}', Colors.blueGrey)),
          Expanded(child: _buildStatItem('Incoming', '${provider.incomingCount}', Colors.green)),
          Expanded(child: _buildStatItem('Outgoing', '${provider.outgoingCount}', Colors.blue)),
          Expanded(child: _buildStatItem('Missed', '${provider.missedCount}', Colors.red)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    CallRecordProvider provider,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Call Records Backed Up',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.searchQuery.isNotEmpty || provider.callTypeFilter != 'all'
                        ? 'No calls match your active filter criteria. Try clearing filters.'
                        : 'Calls will automatically be recorded here after they finish, or you can sync your device history now.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Sync Device Call Log Now'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                    ),
                    onPressed: () async {
                      final count = await provider.syncHistoricalCallLogs();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Imported $count call records')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
