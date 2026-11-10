import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'app_exception.dart';
import 'cache_service.dart';
import 'localization_service.dart';
import 'push_notification_service.dart';

/// Account level operations that are not about a single table.
class AccountService {
  String _t(String key) => LocalizationService().t(key);

  /// Permanently deletes the signed-in account, then clears what this device
  /// kept for it and signs out locally.
  ///
  /// The server side is the `delete-account` edge function. It identifies the
  /// account from the session token, so nothing is sent in the body.
  ///
  /// Throws an [AppException] with a localized message when the account could
  /// not be deleted. In that case nothing on this device is cleared and the
  /// user stays signed in.
  Future<void> deleteAccount() async {
    final user = supabase.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw AppException(
        AppErrorKind.unauthenticated,
        _t('delete_account_failed'),
      );
    }

    try {
      final call = supabase.functions.invoke('delete-account');
      await call.timeout(const Duration(seconds: 60));
    } catch (error) {
      debugPrint('Account deletion failed: $error');
      // A timeout or a dropped connection does not say whether the server
      // finished. Ask before telling the user the account is still there.
      final finished = error is! FunctionException && await _accountIsGone();
      if (!finished) {
        final offline = AppException.from(error).kind == AppErrorKind.network;
        throw AppException(
          offline ? AppErrorKind.network : AppErrorKind.unknown,
          _t(offline ? 'delete_account_offline' : 'delete_account_failed'),
          cause: error,
        );
      }
    }

    await _clearLocalData(user.id);
  }

  /// True only when the auth server states that the account no longer exists.
  Future<bool> _accountIsGone() async {
    try {
      await supabase.auth.getUser().timeout(const Duration(seconds: 10));
      return false;
    } on AuthException catch (error) {
      return error.code == 'user_not_found';
    } catch (_) {
      return false;
    }
  }

  /// Each step is best effort: the account is already gone, so nothing here
  /// may stop the user from reaching the login screen.
  Future<void> _clearLocalData(String userId) async {
    // The fcm_tokens row went with the account, so no push can be sent to
    // this device any more. This resets the push service for the next user.
    await PushNotificationService.instance.deleteToken();

    try {
      await CacheService.instance.clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('usage_consent_$userId');
      await prefs.remove('pending_role');
    } catch (error) {
      debugPrint('Local data cleanup failed: $error');
    }

    try {
      // Local scope: the server sessions were deleted with the account.
      await supabase.auth.signOut(scope: SignOutScope.local);
    } catch (error) {
      debugPrint('Local sign out failed: $error');
    }
  }
}
