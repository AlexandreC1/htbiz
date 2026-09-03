import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show firebaseReady;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op — FCM shows the system tray notification itself.
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  bool _initialized = false;

  /// Safe to call more than once.
  ///
  /// MainShell calls this from initState without awaiting it, so anything that
  /// throws here becomes an unhandled async error. Nothing below is allowed to
  /// escape — push is optional, and the app works without it.
  Future<void> init() async {
    if (_initialized) return;

    // Firebase.initializeApp is allowed to fail at startup (no Play Services,
    // stale google-services.json). Touching FirebaseMessaging.instance in that
    // state throws.
    if (!firebaseReady) {
      debugPrint('Push disabled: Firebase did not initialise');
      return;
    }

    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // `provisional` (iOS quiet notifications) is a grant, and only `denied`
      // and `notDetermined` are refusals — the old check for `denied` alone
      // meant a notDetermined result fell through to registering a token that
      // could never be delivered.
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!granted) {
        debugPrint(
            'Push permission not granted: ${settings.authorizationStatus}');
        return;
      }

      await _saveToken();

      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen(
        (_) => _saveToken(),
        onError: (Object e) => debugPrint('Token refresh stream error: $e'),
      );

      _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen(
        (message) =>
            debugPrint('Foreground push: ${message.notification?.title}'),
        onError: (Object e) => debugPrint('Foreground push stream error: $e'),
      );
    } catch (error) {
      debugPrint('Push initialisation failed: $error');
    }
  }

  Future<void> _saveToken() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      // APNs can take a moment to hand back a token on a cold iOS start.
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 15));
      if (token == null || token.isEmpty) return;

      await client.from('fcm_tokens').upsert(
        {
          'user_id': user.id,
          'token': token,
          'platform':
              defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id, token',
      ).timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint('Failed to save FCM token: $error');
    }
  }

  /// Called on sign-out.
  ///
  /// The old version deleted every row matching the token, across users. That
  /// is right for this device but relied on the fcm_tokens RLS policy to scope
  /// it; the user_id filter makes the intent explicit and survives a policy
  /// change.
  Future<void> deleteToken() async {
    try {
      if (!firebaseReady) return;

      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 10));

      if (token != null && userId != null) {
        await client
            .from('fcm_tokens')
            .delete()
            .eq('token', token)
            .eq('user_id', userId)
            .timeout(const Duration(seconds: 10));
      }

      // Delete the FCM registration last: if the row delete fails we still
      // know the token and can retry, whereas the reverse order loses it.
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('Failed to delete FCM token: $error');
    } finally {
      // Force a fresh registration for whoever signs in next.
      _initialized = false;
      await _tokenRefreshSub?.cancel();
      await _foregroundSub?.cancel();
      _tokenRefreshSub = null;
      _foregroundSub = null;
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
  }
}
