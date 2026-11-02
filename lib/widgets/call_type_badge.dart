import 'package:flutter/material.dart';

/// CallTypeBadge displays an icon and color-coded chip representing call type:
/// - Incoming: Green
/// - Outgoing: Blue
/// - Missed: Red
/// - Rejected: Deep Orange
class CallTypeBadge extends StatelessWidget {
  final String callType;
  final bool showLabel;

  const CallTypeBadge({
    Key? key,
    required this.callType,
    this.showLabel = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final type = callType.toLowerCase();

    Color color;
    IconData icon;
    String label;

    switch (type) {
      case 'incoming':
        color = Colors.green.shade600;
        icon = Icons.call_received;
        label = 'Incoming';
        break;
      case 'outgoing':
        color = Colors.blue.shade600;
        icon = Icons.call_made;
        label = 'Outgoing';
        break;
      case 'missed':
        color = Colors.red.shade600;
        icon = Icons.call_missed;
        label = 'Missed';
        break;
      case 'rejected':
        color = Colors.orange.shade800;
        icon = Icons.call_missed_outgoing;
        label = 'Rejected';
        break;
      default:
        color = Colors.grey.shade600;
        icon = Icons.phone;
        label = callType.toUpperCase();
    }

    if (!showLabel) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 18),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
