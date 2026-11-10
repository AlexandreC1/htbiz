import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache_service.dart';
import 'push_notification_service.dart';

/// Signs the current user out and removes what they left on the device.
///
/// The push token is unregistered first, while the session can still delete
/// its fcm_tokens row. The offline cache (profile, notifications, favorites)
/// is cleared even when the sign out request fails, so the next person using
/// the phone cannot read the previous user's data.
Future<void> signOutAndClearLocalData() async {
  await PushNotificationService.instance.deleteToken();
  try {
    await Supabase.instance.client.auth.signOut();
  } finally {
    await CacheService.instance.clearAll();
  }
}
