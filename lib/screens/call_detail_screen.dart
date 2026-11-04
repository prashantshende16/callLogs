import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/call_record.dart';
import '../providers/call_record_provider.dart';
import '../services/database_helper.dart';
import '../services/native_call_service.dart';
import '../widgets/call_type_badge.dart';

/// CallDetailScreen displays comprehensive details for a call record
/// and includes an interactive voice recording audio player.
class CallDetailScreen extends StatefulWidget {
  final CallRecord record;

  const CallDetailScreen({
    Key? key,
    required this.record,
  }) : super(key: key);

  @override
  State<CallDetailScreen> createState() => _CallDetailScreenState();
}

class _CallDetailScreenState extends State<CallDetailScreen> {
  bool _isPlaying = false;
  int _totalDurationMs = 0;
  int _currentPositionMs = 0;
  Timer? _playbackTimer;
  StreamSubscription<void>? _playbackCompletedSub;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    final path = widget.record.audioPath;
    if (path != null && File(path).existsSync()) {
      final dur = await NativeCallService.getAudioDuration(path);
      if (mounted) {
        setState(() {
          _totalDurationMs = dur;
        });
      }
    }

    _playbackCompletedSub = NativeCallService.audioCompletedStream.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPositionMs = 0;
        });
        _playbackTimer?.cancel();
      }
    });
  }

  void _startTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_isPlaying && mounted) {
        setState(() {
          _currentPositionMs += 200;
          if (_totalDurationMs > 0 && _currentPositionMs >= _totalDurationMs) {
            _currentPositionMs = _totalDurationMs;
            _isPlaying = false;
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> _togglePlayPause() async {
    final path = widget.record.audioPath;
    if (path == null || !File(path).existsSync()) return;

    if (_isPlaying) {
      await NativeCallService.pauseAudio();
      _playbackTimer?.cancel();
      setState(() => _isPlaying = false);
    } else {
      if (_currentPositionMs == 0) {
        final dur = await NativeCallService.playAudio(path);
        if (dur > 0) _totalDurationMs = dur;
      } else {
        await NativeCallService.resumeAudio();
      }
      setState(() => _isPlaying = true);
      _startTimer();
    }
  }

  Future<void> _seek(double val) async {
    final posMs = val.toInt();
    setState(() => _currentPositionMs = posMs);
    await NativeCallService.seekAudio(posMs);
  }

  Future<void> _shareAudio() async {
    final path = widget.record.audioPath;
    if (path != null && File(path).existsSync()) {
      await Share.shareXFiles(
        [XFile(path, mimeType: 'audio/mp4')],
        text: 'Call recording with ${widget.record.callerNumber}',
      );
    }
  }

  Future<void> _searchForNativeRecording() async {
    final path = await NativeCallService.findNativeRecordingForCall(
      number: widget.record.callerNumber,
      startTime: widget.record.startTime,
      endTime: widget.record.endTime,
    );
    if (path != null && widget.record.id != null) {
      await DatabaseHelper.instance.updateAudioPath(widget.record.id!, path);
      if (mounted) {
        Provider.of<CallRecordProvider>(context, listen: false).loadRecords();
        setState(() {});
        _initAudio();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Found, copied, and linked device call recording!')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file auto-matched. Tap "Browse Device" to pick your .wav file!')),
        );
      }
    }
  }

  Future<void> _pickWithSystemFileManager() async {
    final pickedPath = await NativeCallService.pickAudioWithSystemPicker();
    if (pickedPath != null && widget.record.id != null) {
      await DatabaseHelper.instance.updateAudioPath(widget.record.id!, pickedPath);
      if (mounted) {
        Provider.of<CallRecordProvider>(context, listen: false).loadRecords();
        setState(() {});
        _initAudio();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully linked audio recording!')),
        );
      }
    }
  }

  Future<void> _pickFromDeviceRecordings() async {
    final list = await NativeCallService.scanAllNativeRecordings();
    if (!mounted) return;

    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recording files found in standard folders (/Record/Call, /Music/Recordings/...)')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Call Recording File',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Found ${list.length} native recordings on your device. Tap one to back up and link to this call:',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final item = list[index];
                    final name = item['name'] as String? ?? 'Recording';
                    final path = item['path'] as String? ?? '';
                    final ext = (item['extension'] as String? ?? name.split('.').last).toUpperCase();
                    final size = item['size'] as int? ?? 0;
                    final sizeKb = (size / 1024).round();
                    final modTime = item['lastModified'] as int? ?? 0;
                    final dateStr = modTime > 0
                        ? DateFormat('MMM dd, yyyy  hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(modTime))
                        : '';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: ext == 'WAV' ? Colors.blue.shade50 : Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: ext == 'WAV' ? Colors.blue.shade200 : Colors.purple.shade200,
                          ),
                        ),
                        child: Text(
                          ext,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: ext == 'WAV' ? Colors.blue.shade800 : Colors.purple.shade800,
                          ),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('$dateStr  •  ${sizeKb}KB\n$path', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        if (widget.record.id != null) {
                          // Copy to app storage backup
                          final backupPath = await NativeCallService.copyAudioToAppStorage(
                            path,
                            widget.record.callerNumber,
                          ) ?? path;

                          await DatabaseHelper.instance.updateAudioPath(widget.record.id!, backupPath);
                          if (mounted) {
                            Provider.of<CallRecordProvider>(context, listen: false).loadRecords();
                            setState(() {});
                            _initAudio();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Copied and linked $name to this call!')),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _playbackCompletedSub?.cancel();
    NativeCallService.stopAudio();
    super.dispose();
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Call Record'),
        content: Text('Are you sure you want to permanently delete the record for ${widget.record.callerNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.record.id != null) {
      if (context.mounted) {
        await Provider.of<CallRecordProvider>(context, listen: false).deleteRecord(widget.record.id!);
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Call record deleted')),
          );
        }
      }
    }
  }

  String _formatTimeMs(int ms) {
    final sec = (ms / 1000).floor();
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final dateFormat = DateFormat('EEEE, MMMM dd, yyyy  hh:mm:ss a');

    final startString = record.startTime > 0
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(record.startTime))
        : 'N/A';
    final endString = record.endTime > 0
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(record.endTime))
        : 'N/A';
    final createdString = record.createdAt > 0
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(record.createdAt))
        : 'N/A';

    final hasAudio = record.audioPath != null && File(record.audioPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Details'),
        elevation: 0,
        actions: [
          if (hasAudio)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share Call Audio',
              onPressed: _shareAudio,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete Record',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Header Card: Caller & Type
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    CallTypeBadge(callType: record.callType, showLabel: false),
                    const SizedBox(height: 12),
                    Text(
                      record.displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (record.hasContactName)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          record.callerNumber,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CallTypeBadge(callType: record.callType),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy Number',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _copyToClipboard(context, record.callerNumber, 'Caller number'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Voice Recording Player Card
            if (hasAudio) ...[
              Card(
                elevation: 1,
                color: Colors.purple.shade50.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.purple.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.mic, color: Colors.purple.shade800, size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Voice Recording',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.share, size: 20, color: Colors.purple),
                            tooltip: 'Share Recording',
                            onPressed: _shareAudio,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Slider(
                        value: _currentPositionMs.toDouble().clamp(0.0, (_totalDurationMs > 0 ? _totalDurationMs : 1000).toDouble()),
                        max: (_totalDurationMs > 0 ? _totalDurationMs : 1000).toDouble(),
                        onChanged: _seek,
                        activeColor: Colors.purple,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatTimeMs(_currentPositionMs),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                            Text(
                              _formatTimeMs(_totalDurationMs),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.purple.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          ),
                          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                          label: Text(_isPlaying ? 'Pause' : 'Play Recording'),
                          onPressed: _togglePlayPause,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Auto-Detect Recording (.wav / .m4a / .mp3)'),
                  onPressed: _searchForNativeRecording,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.list, size: 16),
                      label: const Text('Scanned Files', style: TextStyle(fontSize: 13)),
                      onPressed: _pickFromDeviceRecordings,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade700),
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Browse Device', style: TextStyle(fontSize: 13)),
                      onPressed: _pickWithSystemFileManager,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Metadata Card
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    _buildDetailRow(
                      icon: Icons.person_outline,
                      label: 'Caller (Sender)',
                      value: record.callerNumber,
                      onCopy: () => _copyToClipboard(context, record.callerNumber, 'Caller number'),
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.phone_android,
                      label: 'Receiver (This Device)',
                      value: record.receiverNumber,
                      onCopy: () => _copyToClipboard(context, record.receiverNumber, 'Receiver number'),
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.info_outline,
                      label: 'Call Status',
                      value: record.callStatus.toUpperCase(),
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.timer_outlined,
                      label: 'Call Duration',
                      value: '${record.formattedDuration} (${record.durationSeconds} seconds)',
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.sim_card_outlined,
                      label: 'SIM Slot / Carrier',
                      value: record.simSlot ?? 'Default SIM',
                    ),
                    if (hasAudio) ...[
                      const Divider(height: 1),
                      _buildDetailRow(
                        icon: Icons.audio_file_outlined,
                        label: 'Recording File',
                        value: record.audioPath!.split('/').last,
                      ),
                    ],
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.play_arrow_outlined,
                      label: 'Call Started',
                      value: startString,
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.stop_outlined,
                      label: 'Call Ended',
                      value: endString,
                    ),
                    const Divider(height: 1),
                    _buildDetailRow(
                      icon: Icons.storage_outlined,
                      label: 'Logged in SQLite',
                      value: createdString,
                    ),
                    if (record.id != null) ...[
                      const Divider(height: 1),
                      _buildDetailRow(
                        icon: Icons.tag,
                        label: 'Database ID',
                        value: '#${record.id}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}
