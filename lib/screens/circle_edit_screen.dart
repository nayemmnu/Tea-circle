import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/circle_service.dart';

class CircleEditScreen extends StatefulWidget {
  const CircleEditScreen({super.key, this.circle});
  final TeaCircle? circle; // null = creating a new one

  @override
  State<CircleEditScreen> createState() => _CircleEditScreenState();
}

class _CircleEditScreenState extends State<CircleEditScreen> {
  final _name = TextEditingController();
  final _message = TextEditingController(text: 'Come for tea ☕');
  final _email = TextEditingController();
  final List<AppUser> _members = [];
  bool _saving = false;
  bool _adding = false;
  String? _error;

  static const _suggestions = [
    'Come for tea ☕',
    "Let's go out 🚶",
    'Tea break? ☕',
    'Lunch time 🍛',
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.circle;
    if (c != null) {
      _name.text = c.name;
      _message.text = c.message;
      final me = CircleService.myUid;
      for (final uid in c.memberIds.where((u) => u != me)) {
        _members.add(AppUser(uid: uid, name: c.nameOf(uid), email: ''));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty) return;
    if (email == FirebaseAuth.instance.currentUser?.email?.toLowerCase()) {
      setState(() => _error = "That's your own email 🙂");
      return;
    }
    setState(() {
      _adding = true;
      _error = null;
    });
    String? error;
    try {
      final u = await CircleService.findUserByEmail(email);
      if (u == null) {
        error = 'No account with that email yet. Ask your friend to install '
            'the app and sign up first.';
      } else if (_members.any((m) => m.uid == u.uid)) {
        error = '${u.name} is already in this circle.';
      } else {
        _members.add(u);
        _email.clear();
      }
    } catch (e) {
      error = 'Could not search: $e';
    }
    if (!mounted) return;
    setState(() {
      _adding = false;
      _error = error;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final message = _message.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the circle a name.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _error = 'Write the message that will be sent on tap.');
      return;
    }
    if (_members.isEmpty) {
      setState(() => _error = 'Add at least one friend.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await CircleService.saveCircle(
        id: widget.circle?.id,
        name: name,
        message: message,
        members: _members,
      ).timeout(const Duration(seconds: 10));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Check your internet connection.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this circle?'),
        content: Text('"${widget.circle!.name}" will be removed for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CircleService.deleteCircle(widget.circle!.id)
          .timeout(const Duration(seconds: 10));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not delete. Check your internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.circle != null;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit circle' : 'New circle'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete circle',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Circle name (e.g. Office Tea)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _message,
            decoration: const InputDecoration(
                labelText: 'Message sent on one tap',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final s in _suggestions)
                ActionChip(
                    label: Text(s), onPressed: () => _message.text = s),
            ],
          ),
          const SizedBox(height: 24),
          Text('Friends in this circle',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _adding ? null : _addMember(),
                  decoration: const InputDecoration(
                      labelText: "Friend's email",
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _adding ? null : _addMember,
                child: _adding
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            Text('Nobody yet. Add friends by the email they signed up with.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          for (final m in _members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                  child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase())),
              title: Text(m.name),
              subtitle: m.email.isEmpty ? null : Text(m.email),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() => _members.remove(m)),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(editing ? 'Save changes' : 'Create circle'),
          ),
        ],
      ),
    );
  }
}
