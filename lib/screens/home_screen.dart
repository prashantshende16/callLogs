import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/call_record_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/call_record_tile.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/search_bar_widget.dart';
import 'settings_screen.dart';

/// HomeScreen renders the transparent call records list, stats bar, search & filter controls.
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final recordProvider = Provider.of<CallRecordProvider>(context, listen: false);

      recordProvider.startListeningToNativeEvents();

      // Trigger one-time initial sync from device call log if not done yet
      if (!settings.hasInitialSyncDone) {
        recordProvider.syncHistoricalCallLogs().then((_) => settings.markInitialSyncDone());
      }
    });
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
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Call Log Keeper',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: settings.isMonitoringEnabled
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
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
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: settings.isMonitoringEnabled
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    settings.isMonitoringEnabled ? 'Active' : 'Paused',
                    style: TextStyle(
                      fontSize: 10.5,
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
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.filter_list, size: 22),
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
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.sync_rounded, size: 22),
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
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.settings_outlined, size: 22),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
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

          // Records List with Pull-to-refresh
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await recordProvider.loadRecords();
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
