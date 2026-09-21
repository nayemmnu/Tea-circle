import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/circle_service.dart';

/// Live board: who is coming (green), who cannot (red), who is offline
/// (grey), who has not answered yet (amber).
class CallStatusScreen extends StatefulWidget {
  const CallStatusScreen(
      {super.key, required this.circle, required this.handle});
  final TeaCircle circle;
  final CallHandle handle;

  @override
  State<CallStatusScreen> createState() => _CallStatusScreenState();
}

class _CallStatusScreenState extends State<CallStatusScreen> {
  /// A friend whose phone has not confirmed receipt after this long is
  /// shown as unavailable (offline).
  static const _waitLimit = Duration(seconds: 45);

  static const _order = {
    'accepted': 0,
    'delivered': 1,
    'pending': 2,
    'declined': 3,
    'unavailable': 4,
  };

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _effective(String? stored) {
    final s = stored ?? 'pending';
    if (s == 'pending' &&
        DateTime.now().difference(widget.handle.startedAt) > _waitLimit) {
      return 'unavailable';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final circle = widget.circle;
    final callRef = FirebaseFirestore.instance
        .doc('groups/${circle.id}/calls/${widget.handle.id}');
    final me = CircleService.myUid;

    return Scaffold(
      appBar: AppBar(title: Text(circle.name)),
      body: Column(
        children: [
          // problem while sending notifications
          FutureBuilder<String?>(
            future: widget.handle.pushResult,
            builder: (context, snap) {
              final err = snap.data;
              if (err == null) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Colors.red.shade100,
                padding: const EdgeInsets.all(10),
                child: Text(err, style: const TextStyle(color: Colors.black87)),
              );
            },
          ),
          // "still sending" banner while the phone has no connection
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: callRef.snapshots(includeMetadataChanges: true),
            builder: (context, snap) {
              final sending =
                  snap.hasData && snap.data!.metadata.hasPendingWrites;
              if (!sending) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Colors.orange.shade200,
                padding: const EdgeInsets.all(10),
                child: const Text(
                  'Sending… waiting for a connection.',
                  style: TextStyle(color: Colors.black87),
                ),
              );
            },
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text('"${circle.message}"',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: callRef.collection('responses').snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final byUid = <String, String>{
                  for (final d in snap.data?.docs ?? const [])
                    d.id: (d.data()['status'] as String?) ?? 'pending',
                };
                final entries = circle.memberIds
                    .map((uid) => MapEntry(
                        uid, uid == me ? 'accepted' : _effective(byUid[uid])))
                    .toList()
                  ..sort((a, b) =>
                      (_order[a.value] ?? 9).compareTo(_order[b.value] ?? 9));

                int count(bool Function(String) f) =>
                    entries.where((e) => f(e.value)).length;
                final coming = count((s) => s == 'accepted');
                final busy = count((s) => s == 'declined');
                final offline = count((s) => s == 'unavailable');
                final waiting =
                    count((s) => s == 'pending' || s == 'delivered');

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _chip(Colors.green.shade600, '$coming coming'),
                          _chip(Colors.red.shade600, "$busy can't"),
                          _chip(Colors.grey.shade600, '$offline offline'),
                          _chip(Colors.amber.shade800, '$waiting waiting'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final e in entries)
                            _row(
                                circle.nameOf(e.key) +
                                    (e.key == me ? ' (You)' : ''),
                                e.value),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(Color color, String label) => Chip(
        avatar: CircleAvatar(backgroundColor: color, radius: 6),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      );

  Widget _row(String name, String status) {
    final info = statusInfo(status);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: info.color,
        child: Icon(info.icon, color: Colors.white),
      ),
      title: Text(name),
      subtitle: Text(info.label),
    );
  }
}
