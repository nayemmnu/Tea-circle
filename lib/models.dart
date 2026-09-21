import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AppUser {
  const AppUser({required this.uid, required this.name, required this.email});
  final String uid;
  final String name;
  final String email;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppUser(
      uid: d.id,
      name: (m['name'] ?? '') as String,
      email: (m['email'] ?? '') as String,
    );
  }
}

/// A "circle" = a group of close friends with a preset message.
class TeaCircle {
  const TeaCircle({
    required this.id,
    required this.name,
    required this.message,
    required this.ownerId,
    required this.memberIds,
    required this.memberNames,
  });

  final String id;
  final String name;
  final String message;
  final String ownerId;
  final List<String> memberIds;
  final Map<String, String> memberNames;

  factory TeaCircle.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return TeaCircle(
      id: d.id,
      name: (m['name'] ?? '') as String,
      message: (m['message'] ?? '') as String,
      ownerId: (m['ownerId'] ?? '') as String,
      memberIds: List<String>.from(m['memberIds'] ?? const []),
      memberNames: Map<String, String>.from(m['memberNames'] ?? const {}),
    );
  }

  String nameOf(String uid) => memberNames[uid] ?? 'Friend';
}

/// A tea call somebody else sent to a circle I belong to.
class Invite {
  const Invite({
    required this.groupId,
    required this.callId,
    required this.groupName,
    required this.message,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
  });

  final String groupId;
  final String callId;
  final String groupName;
  final String message;
  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;

  factory Invite.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Invite(
      groupId: d.reference.parent.parent!.id,
      callId: d.id,
      groupName: (m['groupName'] ?? '') as String,
      message: (m['message'] ?? '') as String,
      createdBy: (m['createdBy'] ?? '') as String,
      createdByName: (m['createdByName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class StatusInfo {
  const StatusInfo(this.color, this.label, this.icon);
  final Color color;
  final String label;
  final IconData icon;
}

/// Maps a response status to its colour / label.
///   accepted    -> green  (free and coming)
///   declined    -> red    (busy)
///   unavailable -> grey   (phone did not receive it: offline)
///   delivered   -> amber  (phone got it, no answer yet)
///   pending     -> amber  (sent, waiting)
StatusInfo statusInfo(String? status) {
  switch (status) {
    case 'accepted':
      return StatusInfo(Colors.green.shade600, 'Coming', Icons.check_circle);
    case 'declined':
      return StatusInfo(Colors.red.shade600, "Can't come", Icons.cancel);
    case 'unavailable':
      return StatusInfo(
          Colors.grey.shade600, 'Unavailable (offline)', Icons.wifi_off);
    case 'delivered':
      return StatusInfo(Colors.amber.shade800, 'Notified, no reply yet',
          Icons.notifications_active);
    default:
      return StatusInfo(Colors.amber.shade700, 'Waiting…', Icons.hourglass_top);
  }
}
