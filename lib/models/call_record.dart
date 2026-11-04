import 'package:intl/intl.dart';

/// CallRecord model represents an incoming, outgoing, missed, or rejected call.
class CallRecord {
  final int? id;
  final String callerNumber;
  final String? callerName;
  final String receiverNumber;
  final String callType; // 'incoming', 'outgoing', 'missed', 'rejected'
  final String callStatus; // 'ringing', 'connected', 'ended'
  final int startTime; // epoch milliseconds
  final int endTime; // epoch milliseconds
  final int durationSeconds;
  final String? simSlot;
  final String? audioPath;
  final int createdAt; // epoch milliseconds

  CallRecord({
    this.id,
    required this.callerNumber,
    this.callerName,
    required this.receiverNumber,
    required this.callType,
    required this.callStatus,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    this.simSlot,
    this.audioPath,
    required this.createdAt,
  });

  /// Factory constructor to deserialize from SQLite map
  factory CallRecord.fromMap(Map<String, dynamic> map) {
    return CallRecord(
      id: map['id'] as int?,
      callerNumber: map['caller_number'] as String? ?? 'Unknown',
      callerName: map['caller_name'] as String?,
      receiverNumber: map['receiver_number'] as String? ?? 'Unknown',
      callType: (map['call_type'] as String? ?? 'incoming').toLowerCase(),
      callStatus: (map['call_status'] as String? ?? 'ended').toLowerCase(),
      startTime: map['start_time'] as int? ?? 0,
      endTime: map['end_time'] as int? ?? 0,
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      simSlot: map['sim_slot'] as String?,
      audioPath: map['audio_path'] as String?,
      createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Converts the record to an SQLite map
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'caller_number': callerNumber,
      'caller_name': callerName,
      'receiver_number': receiverNumber,
      'call_type': callType.toLowerCase(),
      'call_status': callStatus.toLowerCase(),
      'start_time': startTime,
      'end_time': endTime,
      'duration_seconds': durationSeconds,
      'sim_slot': simSlot,
      'audio_path': audioPath,
      'created_at': createdAt,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  CallRecord copyWith({
    int? id,
    String? callerNumber,
    String? callerName,
    String? receiverNumber,
    String? callType,
    String? callStatus,
    int? startTime,
    int? endTime,
    int? durationSeconds,
    String? simSlot,
    String? audioPath,
    int? createdAt,
  }) {
    return CallRecord(
      id: id ?? this.id,
      callerNumber: callerNumber ?? this.callerNumber,
      callerName: callerName ?? this.callerName,
      receiverNumber: receiverNumber ?? this.receiverNumber,
      callType: callType ?? this.callType,
      callStatus: callStatus ?? this.callStatus,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      simSlot: simSlot ?? this.simSlot,
      audioPath: audioPath ?? this.audioPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Best display name: contact name if known, else caller number, else 'Unknown'
  String get displayName {
    if (callerName != null && callerName!.trim().isNotEmpty && callerName!.trim().toLowerCase() != 'unknown') {
      return callerName!.trim();
    }
    if (callerNumber.trim().isNotEmpty && callerNumber.trim().toLowerCase() != 'unknown') {
      return callerNumber.trim();
    }
    return 'Unknown';
  }

  /// Whether a recognized contact name is available separate from the phone number
  bool get hasContactName {
    return callerName != null &&
        callerName!.trim().isNotEmpty &&
        callerName!.trim().toLowerCase() != 'unknown' &&
        callerName!.trim() != callerNumber.trim();
  }

  /// Formatted duration in "MM:SS" or "Xh Ym Zs"
  String get formattedDuration {
    if (durationSeconds <= 0) return '0s';
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Formatted start date & time (e.g. "Oct 30, 2026, 04:15 PM")
  String get formattedDateTime {
    if (startTime <= 0) return 'Unknown';
    final dt = DateTime.fromMillisecondsSinceEpoch(startTime);
    return DateFormat('MMM dd, yyyy  hh:mm a').format(dt);
  }

  /// Formatted relative or short time
  String get formattedShortTime {
    if (startTime <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(startTime);
    final now = DateTime.now();

    if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
      return DateFormat('hh:mm a').format(dt);
    } else if (now.year == dt.year) {
      return DateFormat('MMM dd, hh:mm a').format(dt);
    }
    return DateFormat('MM/dd/yy hh:mm a').format(dt);
  }

  /// Helper for UI icons & colors
  bool get isIncoming => callType == 'incoming';
  bool get isOutgoing => callType == 'outgoing';
  bool get isMissed => callType == 'missed';
  bool get isRejected => callType == 'rejected';
}

