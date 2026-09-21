import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/circle_service.dart';
import '../services/notification_service.dart';
import '../widgets/invite_card.dart';
import 'call_status_screen.dart';
import 'circle_edit_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<List<TeaCircle>> _circles = CircleService.myCircles();
  late final Stream<List<Invite>> _invites = CircleService.activeInvites();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    NotificationService.registerToken();
    // re-filter old invites every 30 s
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// ONE TAP: shows a 4-second UNDO bar, then sends the call.
  Future<void> _sendCall(TeaCircle c) async {
    if (c.memberIds.length < 2) {
      _snack('Add at least one friend to "${c.name}" first (tap the pencil).');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final ctrl = messenger.showSnackBar(SnackBar(
      content: Text('Sending "${c.message}" to ${c.name}…'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(label: 'UNDO', onPressed: () {}),
    ));
    final reason = await ctrl.closed;
    final send = reason == SnackBarClosedReason.timeout ||
        reason == SnackBarClosedReason.swipe ||
        reason == SnackBarClosedReason.dismiss;
    if (!send || !mounted) return;

    final callId = CircleService.startCall(c);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallStatusScreen(circle: c, callId: callId),
      ),
    );
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will stop receiving tea calls on this phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await NotificationService.unregister();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = CircleService.myUid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('☕ Tea Circles'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CircleEditScreen()),
        ),
        icon: const Icon(Icons.group_add),
        label: const Text('New circle'),
      ),
      body: Column(
        children: [
          // ---- incoming calls from friends
          StreamBuilder<List<Invite>>(
            stream: _invites,
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Could not load invites: ${snap.error}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                );
              }
              final now = DateTime.now();
              final list = (snap.data ?? [])
                  .where((i) =>
                      i.createdBy != myUid &&
                      i.createdAt != null &&
                      now.difference(i.createdAt!).inMinutes < 10)
                  .toList()
                ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
              if (list.isEmpty) return const SizedBox.shrink();
              return Column(
                children: list
                    .take(3)
                    .map((i) => InviteCard(
                        key: ValueKey('${i.groupId}/${i.callId}'), invite: i))
                    .toList(),
              );
            },
          ),
          // ---- my circles
          Expanded(
            child: StreamBuilder<List<TeaCircle>>(
              stream: _circles,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final circles = snap.data!;
                if (circles.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No circles yet.\n\nCreate one, add your tea-break friends, '
                        'and set a message like "Come for tea ☕".',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Tap a circle to call everyone in it',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ),
                    for (final c in circles) _circleCard(c, myUid),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleCard(TeaCircle c, String myUid) {
    final scheme = Theme.of(context).colorScheme;
    final others = c.memberIds.where((u) => u != myUid).map(c.nameOf).toList();
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _sendCall(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                child: const Text('☕', style: TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('"${c.message}"',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      others.isEmpty ? 'No friends added yet' : others.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (c.ownerId == myUid)
                IconButton(
                  tooltip: 'Edit circle',
                  icon: const Icon(Icons.edit),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CircleEditScreen(circle: c)),
                  ),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
