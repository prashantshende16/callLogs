import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// FilterSheet modal bottom sheet for filtering calls by type and date range
class FilterSheet extends StatefulWidget {
  final String currentType;
  final DateTime? currentStartDate;
  final DateTime? currentEndDate;
  final Function(String type, DateTime? start, DateTime? end) onApply;
  final VoidCallback onReset;

  const FilterSheet({
    Key? key,
    required this.currentType,
    required this.currentStartDate,
    required this.currentEndDate,
    required this.onApply,
    required this.onReset,
  }) : super(key: key);

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late String _selectedType;
  DateTime? _startDate;
  DateTime? _endDate;

  final List<Map<String, String>> _types = [
    {'value': 'all', 'label': 'All Calls'},
    {'value': 'incoming', 'label': 'Incoming'},
    {'value': 'outgoing', 'label': 'Outgoing'},
    {'value': 'missed', 'label': 'Missed'},
    {'value': 'rejected', 'label': 'Rejected'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentType;
    _startDate = widget.currentStartDate;
    _endDate = widget.currentEndDate;
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? now),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _setDatePreset(String preset) {
    final now = DateTime.now();
    setState(() {
      switch (preset) {
        case 'today':
          _startDate = DateTime(now.year, now.month, now.day);
          _endDate = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          _startDate = now.subtract(Duration(days: now.weekday - 1));
          _endDate = now;
          break;
        case 'month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = now;
          break;
        case 'all':
          _startDate = null;
          _endDate = null;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filter Call Records',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    widget.onReset();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Reset All'),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),

            // Call Type Selection
            const Text(
              'Call Type',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _types.map((t) {
                final isSelected = _selectedType == t['value'];
                return ChoiceChip(
                  label: Text(t['label']!),
                  selected: isSelected,
                  selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: isSelected ? Theme.of(context).primaryColor : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _selectedType = t['value']!;
                      });
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Date Range Presets
            const Text(
              'Quick Date Presets',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _setDatePreset('today'),
                  child: const Text('Today'),
                ),
                OutlinedButton(
                  onPressed: () => _setDatePreset('week'),
                  child: const Text('This Week'),
                ),
                OutlinedButton(
                  onPressed: () => _setDatePreset('month'),
                  child: const Text('This Month'),
                ),
                OutlinedButton(
                  onPressed: () => _setDatePreset('all'),
                  child: const Text('Any Time'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Custom Date Range Pickers
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('From', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text(
                            _startDate != null ? dateFormat.format(_startDate!) : 'Select Date',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _startDate != null ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('To', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text(
                            _endDate != null ? dateFormat.format(_endDate!) : 'Select Date',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _endDate != null ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Apply Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  widget.onApply(_selectedType, _startDate, _endDate);
                  Navigator.of(context).pop();
                },
                child: const Text('Apply Filters', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

