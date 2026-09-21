import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis_auth/auth_io.dart';

import '../models.dart';

/// Sends the push notifications straight from the caller's phone, so no
/// server (and no paid plan) is needed.
///
/// It uses a restricted Google service account (role: "Firebase Cloud
/// Messaging API Admin") that the GitHub build stores in
/// assets/fcm_service_account.json.
class PushSender {
  PushSender._();

  /// Returns null when everything was sent, otherwise a message for the user.
  static Future<String?> sendCall({
    required TeaCircle circle,
    required String callId,
    required String callerUid,
    required String callerName,
    required String message,
  }) async {
    Map<String, dynamic> key;
    try {
      key = jsonDecode(
              await rootBundle.loadString('assets/fcm_service_account.json'))
          as Map<String, dynamic>;
    } catch (_) {
      key = {};
    }
    if (key['private_key'] == null || key['project_id'] == null) {
      return 'Push sending is not set up in this build (FCM_SERVICE_ACCOUNT '
          'secret missing). Friends will only see the call when they open the app.';
    }

    final targets = circle.memberIds.where((u) => u != callerUid).toList();
    AutoRefreshingAuthClient? client;
    try {
      final c = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(key),
        ['https://www.googleapis.com/auth/firebase.messaging'],
      );
      client = c;
      final url = Uri.parse(
          'https://fcm.googleapis.com/v1/projects/${key['project_id']}/messages:send');

      var failed = 0;
      String? firstError;

      await Future.wait(targets.map((uid) async {
        // Friends who never opened the app have no token: they simply will
        // not answer and show up as "unavailable".
        final snap =
            await FirebaseFirestore.instance.collection('tokens').doc(uid).get();
        final token = snap.data()?['token'] as String?;
        if (token == null) return;

        final res = await c.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': {
              'token': token,
              // data-only: the app builds the notification itself so it can
              // add the buttons and confirm delivery.
              'data': {
                'type': 'tea_call',
                'groupId': circle.id,
                'callId': callId,
                'uid': uid,
                'groupName': circle.name,
                'callerName': callerName,
                'message': message,
              },
              'android': {
                'priority': 'HIGH',
                'ttl': '60s', // an offline phone must not get a stale invite
              },
            },
          }),
        );
        if (res.statusCode >= 300) {
          // 404 = that friend's token is dead (app uninstalled): not our error.
          if (res.statusCode == 404) return;
          failed++;
          firstError ??= 'HTTP ${res.statusCode}: '
              '${res.body.length > 160 ? res.body.substring(0, 160) : res.body}';
        }
      }));

      if (failed > 0) {
        return 'Could not notify $failed friend(s). $firstError';
      }
      return null;
    } catch (e) {
      return 'Could not send notifications (are you online?): $e';
    } finally {
      client?.close();
    }
  }
}
