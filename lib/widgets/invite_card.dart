import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/circle_service.dart';

/// In-app version of the notification: shown at the top of the home screen
/// when a friend has called one of my circles. Also a fallback for phones that
/// block notifications.
class InviteCard extends StatefulWidget {
  const InviteCard({super.key, required this.invite});
  final Invite invite;

  @override
  State<InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<InviteCard> {
  bool _ackSent = false;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .doc('groups/${widget.invite.groupId}/calls/${widget.invite.callId}'
              '/responses/${CircleService.myUid}')
          .snapshots();

  Future<void> _answer(String status) async {
    try {
      await CircleService.respond(
        groupId: widget.invite.groupId,
        callId: widget.invite.callId,
        status: status,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not send your reply. Check your internet.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.invite;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final exists = snap.data?.exists ?? false;
        final status = snap.data?.data()?['status'] as String?;

        // The app is open and online, so tell the server we received it.
        if (exists &&
            !_ackSent &&
            (status == 'pending' || status == 'unavailable')) {
          _ackSent = true;
          CircleService.respond(
                  groupId: i.groupId, callId: i.callId, status: 'delivered')
              .catchError((_) {});
        }

        final coming = status == 'accepted';
        final declined = status == 'declined';

        return Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('☕ ${i.groupName}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${i.createdByName}: ${i.message}',
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: coming
                          ? FilledButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.check),
                              label: const Text("You're coming"),
                              style: FilledButton.styleFrom(
                                  disabledBackgroundColor:
                                      Colors.green.shade600,
                                  disabledForegroundColor: Colors.white),
                            )
                          : OutlinedButton.icon(
                              onPressed: () => _answer('accepted'),
                              icon: Icon(Icons.check,
                                  color: Colors.green.shade700),
                              label: const Text("I'm coming"),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: declined
                          ? FilledButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.close),
                              label: const Text("Can't"),
                              style: FilledButton.styleFrom(
                                  disabledBackgroundColor: Colors.red.shade600,
                                  disabledForegroundColor: Colors.white),
                            )
                          : OutlinedButton.icon(
                              onPressed: () => _answer('declined'),
                              icon:
                                  Icon(Icons.close, color: Colors.red.shade700),
                              label: const Text("Can't"),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
