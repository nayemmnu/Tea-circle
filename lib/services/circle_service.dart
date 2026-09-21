import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart';

/// All Firestore access lives here.
class CircleService {
  CircleService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static User get _me => FirebaseAuth.instance.currentUser!;

  static String get myUid => _me.uid;
  static String get myName {
    final n = _me.displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return _me.email ?? 'Me';
  }

  /// Public profile so friends can find me by email.
  static Future<void> saveProfile({String? name}) async {
    await _db.collection('users').doc(_me.uid).set({
      'name': name ?? myName,
      'email': (_me.email ?? '').toLowerCase(),
    }, SetOptions(merge: true));
  }

  static Future<AppUser?> findUserByEmail(String email) async {
    final q = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return AppUser.fromDoc(q.docs.first);
  }

  // ------------------------------------------------------------ circles

  static Stream<List<TeaCircle>> myCircles() {
    return _db
        .collection('groups')
        .where('memberIds', arrayContains: myUid)
        .snapshots()
        .map((s) {
      final list = s.docs.map(TeaCircle.fromDoc).toList();
      list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  static Future<void> saveCircle({
    String? id,
    required String name,
    required String message,
    required List<AppUser> members,
  }) async {
    final ids = <String>[
      myUid,
      ...members.map((m) => m.uid).where((u) => u != myUid),
    ];
    final names = <String, String>{
      myUid: myName,
      for (final m in members) m.uid: m.name,
    };
    final data = {
      'name': name,
      'message': message,
      'memberIds': ids,
      'memberNames': names,
    };
    if (id == null) {
      await _db.collection('groups').add({
        ...data,
        'ownerId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _db.collection('groups').doc(id).update(data);
    }
  }

  static Future<void> deleteCircle(String id) =>
      _db.collection('groups').doc(id).delete();

  // ------------------------------------------------------------ calls

  /// One tap on a circle. Returns the new call id immediately; the write is
  /// queued by Firestore if the phone is offline. A Cloud Function then sends
  /// the push notifications.
  static String startCall(TeaCircle c) {
    final ref = _db.collection('groups').doc(c.id).collection('calls').doc();
    ref.set({
      'createdBy': myUid,
      'createdByName': myName,
      'message': c.message,
      'groupName': c.name,
      'memberIds': c.memberIds,
      'createdAt': FieldValue.serverTimestamp(),
    }).catchError((_) {});
    return ref.id;
  }

  /// Calls (last 10 minutes) sent to circles I belong to.
  static Stream<List<Invite>> activeInvites() {
    final cutoff =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 10)));
    return _db
        .collectionGroup('calls')
        .where('memberIds', arrayContains: myUid)
        .where('createdAt', isGreaterThan: cutoff)
        .snapshots()
        .map((s) => s.docs.map(Invite.fromDoc).toList());
  }

  /// Write my answer. Never downgrades an answer (accepted/declined) to
  /// "delivered". Uses a transaction, so it fails when offline instead of
  /// silently queueing a stale answer.
  static Future<void> respond({
    required String groupId,
    required String callId,
    String? uid,
    required String status,
  }) async {
    final ref =
        _db.doc('groups/$groupId/calls/$callId/responses/${uid ?? myUid}');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?['status'] as String?) ?? 'pending';
      if (status == 'delivered' &&
          (current == 'delivered' ||
              current == 'accepted' ||
              current == 'declined')) {
        return;
      }
      tx.set(
        ref,
        {'status': status, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    });
  }
}
