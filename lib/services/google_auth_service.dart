import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Both auth screens share the SDK's single initialization.
class GoogleAuthService {
  static Future<void>? _initialization;

  static Future<GoogleSignInAccount> authenticate() async {
    try {
      await (_initialization ??= GoogleSignIn.instance.initialize(
        serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'] ??
            '85584991269-f04tu8dt4pn7vhn4ipijtaqocmb613qh.apps.googleusercontent.com',
      ));
    } catch (_) {
      _initialization = null;
      rethrow;
    }
    return GoogleSignIn.instance.authenticate();
  }
}
