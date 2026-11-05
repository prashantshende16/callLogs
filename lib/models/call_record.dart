import 'package:intl/intl.dart';

/// CallRecord model represents a transparent call history entry in Call Log Keeper.
/// Matches SQLite table: call_records (number, name, type, date, duration)
class CallRecord {
  final int? id;
  final String number;
  final String? name;
  final int type; // 1: Incoming, 2: Outgoing, 3: Missed, 5: Rejected, 6: Blocked
  final int date; // Epoch timestamp in milliseconds
  final int duration; // Call talk duration in seconds
  final String? audioPath;

  CallRecord({
    this.id,
    required this.number,
    this.name,
    required this.type,
    required this.date,
    required this.duration,
    this.audioPath,
  });

  /// Factory constructor to deserialize from SQLite map
  factory CallRecord.fromMap(Map<String, dynamic> map) {
    return CallRecord(
      id: map['id'] as int?,
      number: map['number'] as String? ?? (map['caller_number'] as String? ?? 'Unknown'),
      name: map['name'] as String? ?? map['caller_name'] as String?,
      type: _parseType(map['type'] ?? map['call_type']),
      date: (map['date'] as int?) ?? (map['start_time'] as int?) ?? 0,
      duration: (map['duration'] as int?) ?? (map['duration_seconds'] as int?) ?? 0,
      audioPath: map['audio_path'] as String?,
    );
  }

  static int _parseType(dynamic val) {
    if (val is int) return val;
    if (val is String) {
      switch (val.toLowerCase()) {
        case 'incoming':
          return 1;
        case 'outgoing':
          return 2;
        case 'missed':
          return 3;
        case 'rejected':
        case 'blocked':
          return 5;
        default:
          return 1;
      }
    }
    return 1;
  }

  /// Converts the record to an SQLite map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'number': number,
      'name': name,
      'type': type,
      'date': date,
      'duration': duration,
    };
  }

  // --- Convenience Getters ---
  String get callerNumber => number;
  String? get callerName => name;
  int get startTime => date;
  int get endTime => date + (duration * 1000);
  int get durationSeconds => duration;
  int get createdAt => date;
  String get receiverNumber => 'My Device';
  String? get simSlot => null;

  bool get isIncoming => type == 1;
  bool get isOutgoing => type == 2;
  bool get isMissed => type == 3;
  bool get isRejected => type == 5 || type == 6;

  String get callType {
    if (isIncoming) return 'incoming';
    if (isOutgoing) return 'outgoing';
    if (isMissed) return 'missed';
    if (isRejected) return 'rejected';
    return 'incoming';
  }

  String get callTypeLabel {
    switch (type) {
      case 1:
        return 'Incoming';
      case 2:
        return 'Outgoing';
      case 3:
        return 'Missed';
      case 5:
        return 'Rejected';
      case 6:
        return 'Blocked';
      default:
        return 'Call';
    }
  }

  /// Formatted date/time: e.g. "Nov 5, 2026 • 11:45 AM"
  String get formattedDate {
    if (date <= 0) return 'Unknown Date';
    final dt = DateTime.fromMillisecondsSinceEpoch(date);
    return DateFormat('MMM d, y • h:mm a').format(dt);
  }

  String get formattedShortTime => shortDate;

  bool get hasContactName => name != null && name!.trim().isNotEmpty && name != 'Unknown' && name != number;

  String get displayName => displayTitle;

  bool get hasAudio => audioPath != null && audioPath!.trim().isNotEmpty;
  String get status => isMissed || isRejected ? 'missed' : 'ended';
  String get callStatus => status;

  /// Short date for lists: e.g. "Today 11:45 AM" or "Nov 5"
  String get shortDate {
    if (date <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(date);
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today, ${DateFormat('h:mm a').format(dt)}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday, ${DateFormat('h:mm a').format(dt)}';
    }
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  /// Formatted duration string (e.g. "02:15" or "1h 10m" or "Missed")
  String get formattedDuration {
    if (isMissed || isRejected) return callTypeLabel;
    if (duration == 0) return '0s';

    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    final hours = minutes ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes % 60}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  /// Display name preferring contact name over raw phone number
  String get displayTitle {
    if (name != null && name!.trim().isNotEmpty && name != 'Unknown') {
      return name!.trim();
    }
    return number.isNotEmpty ? number : 'Unknown Caller';
  }
}
