import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Google Maps configuration, read from the bundled `.env`.
///
/// This key was previously a `static const String _mapsApiKey = 'AIza...'`
/// repeated in four screens. Unlike the Firebase client key, a Maps key is
/// attached to billable APIs — an unrestricted one that leaks can be used by
/// anyone against your quota, at your cost.
///
/// Keeping it out of git is only half the fix, because it still ships in the
/// app bundle. Restrict it in the Google Cloud console:
///   * Application restrictions → Android apps → package name + SHA-1
///   * API restrictions → only Maps SDK for Android, and the Static Maps /
///     Geocoding APIs this app actually calls
/// and set a billing budget alert on the project.
class MapsConfig {
  const MapsConfig._();

  static String get apiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  /// Whether map features can work at all. Screens use this to show a fallback
  /// instead of firing requests that will come back 403.
  static bool get isConfigured => apiKey.isNotEmpty;
}
