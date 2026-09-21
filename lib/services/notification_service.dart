import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'circle_service.dart';

/// Runs when a push arrives while the app is in the background / killed.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.initLocal();
  await NotificationService.handleIncoming(message.data);
}

/// Runs when the user taps ✅ / ❌ on the notification while the app is closed.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.initLocal();
  await NotificationService.handleResponse(response);
}

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'tea_calls',
    'Tea calls',
    description: 'Invitations from your circles',
    importance: Importance.max,
  );

  static Future<void> initLocal() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: handleResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    _ready = true;
  }

  /// Call once from main().
  static Future<void> init() async {
    await initLocal();
    // App open: FCM does not show anything itself, so we do.
    FirebaseMessaging.onMessage.listen((m) => handleIncoming(m.data));
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
  }

  /// Call after login.
  static Future<void> registerToken() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
    } catch (_) {}
  }

  /// Call before logout so this phone stops receiving this account's calls.
  static Future<void> unregister() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        await FirebaseFirestore.instance
            .collection('tokens')
            .doc(u.uid)
            .delete()
            .timeout(const Duration(seconds: 5));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  static Future<void> _saveToken(String token) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    await FirebaseFirestore.instance.collection('tokens').doc(u.uid).set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ------------------------------------------------------------ incoming

  /// A "tea_call" push arrived: show the notification, then tell the server
  /// "this phone received it" (that is what keeps me from being marked
  /// unavailable).
  static Future<void> handleIncoming(Map<String, dynamic> data) async {
    if (data['type'] != 'tea_call') return;
    await initLocal();

    final groupId = data['groupId'] as String?;
    final callId = data['callId'] as String?;
    final uid = data['uid'] as String?;
    if (groupId == null || callId == null || uid == null) return;

    await _plugin.show(
      _idFor(callId),
      '☕ ${data['groupName'] ?? 'Tea call'}',
      '${data['callerName'] ?? 'Someone'}: ${data['message'] ?? ''}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'tea_calls',
          'Tea calls',
          channelDescription: 'Invitations from your circles',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.event,
          timeoutAfter: 600000, // disappears after 10 minutes
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction('accept', "✅ I'm coming"),
            AndroidNotificationAction('decline', "❌ Can't"),
          ],
        ),
      ),
      payload: jsonEncode({'groupId': groupId, 'callId': callId, 'uid': uid}),
    );

    try {
      await CircleService.respond(
        groupId: groupId,
        callId: callId,
        uid: uid,
        status: 'delivered',
      );
    } catch (_) {}
  }

  /// User tapped ✅ or ❌ on the notification.
  static Future<void> handleResponse(NotificationResponse r) async {
    final action = r.actionId;
    if (action != 'accept' && action != 'decline') return; // plain tap = open app

    Map<String, dynamic> p;
    try {
      p = jsonDecode(r.payload ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final groupId = p['groupId'] as String?;
    final callId = p['callId'] as String?;
    final uid = p['uid'] as String?;
    if (groupId == null || callId == null || uid == null) return;

    try {
      await CircleService.respond(
        groupId: groupId,
        callId: callId,
        uid: uid,
        status: action == 'accept' ? 'accepted' : 'declined',
      );
    } catch (_) {
      await _plugin.show(
        _idFor(callId) + 1,
        'Reply not sent',
        'No internet. Open the app and answer when you are online.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'tea_calls',
            'Tea calls',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }
  }

  static int _idFor(String callId) => callId.hashCode & 0x3fffffff;
}
