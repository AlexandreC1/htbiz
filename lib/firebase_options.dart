import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Firebase client configuration, read from the bundled `.env`.
///
/// These values are not secrets in the cryptographic sense — they ship inside
/// every APK and IPA, and anyone can pull them out of a published build. What
/// protects a Firebase project is Security Rules, App Check, and API key
/// restrictions in the Google Cloud console, not the key being unknown.
///
/// They are still kept out of git: `google-services.json` is already ignored,
/// so hard-coding the same values here was inconsistent, and a literal
/// `AIza...` string in a tracked file trips GitHub secret scanning on every
/// push. Sourcing them from `.env` matches how [SupabaseConfig] already works.
///
/// Regenerate the underlying values with `flutterfire configure`, then copy
/// them into `.env` — see `.env.example` for the full list.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Firebase is not configured for $defaultTargetPlatform',
        );
    }
  }

  static String _env(String key) => dotenv.env[key] ?? '';

  /// True when the bundled .env actually carries a usable Android config.
  ///
  /// `main()` treats a Firebase failure as non-fatal, so an incomplete .env
  /// degrades to "no push notifications" rather than a crash on launch.
  static bool get isConfigured =>
      _env('FIREBASE_ANDROID_API_KEY').isNotEmpty &&
      _env('FIREBASE_ANDROID_APP_ID').isNotEmpty &&
      _env('FIREBASE_PROJECT_ID').isNotEmpty;

  static FirebaseOptions get android => FirebaseOptions(
        apiKey: _env('FIREBASE_ANDROID_API_KEY'),
        appId: _env('FIREBASE_ANDROID_APP_ID'),
        messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _env('FIREBASE_PROJECT_ID'),
        storageBucket: _env('FIREBASE_STORAGE_BUCKET'),
      );

  static FirebaseOptions get ios => FirebaseOptions(
        apiKey: _env('FIREBASE_IOS_API_KEY'),
        appId: _env('FIREBASE_IOS_APP_ID'),
        messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _env('FIREBASE_PROJECT_ID'),
        storageBucket: _env('FIREBASE_STORAGE_BUCKET'),
        iosBundleId: _env('FIREBASE_IOS_BUNDLE_ID'),
      );
}
