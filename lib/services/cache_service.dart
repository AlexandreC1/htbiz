import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight JSON cache backed by SharedPreferences.
/// Used for read-side offline support: services try the network first, save
/// successful responses here, and fall back to cached data when offline.
class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  static const _prefix = 'htbiz_cache_';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  String _key(String key) => '$_prefix$key';

  /// Save a JSON-serializable value (List or Map). Stored alongside a timestamp.
  Future<void> save(String key, Object value) async {
    final prefs = await _prefs;
    final wrapped = {
      'savedAt': DateTime.now().toIso8601String(),
      'data': value,
    };
    await prefs.setString(_key(key), jsonEncode(wrapped));
  }

  /// Read a cached List of JSON maps. Returns null if no cache exists.
  Future<List<Map<String, dynamic>>?> readList(String key) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(key));
    if (raw == null) return null;
    try {
      final wrapped = jsonDecode(raw) as Map<String, dynamic>;
      final data = wrapped['data'] as List;
      return data.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  /// Read a cached JSON map. Returns null if no cache exists.
  Future<Map<String, dynamic>?> readMap(String key) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(key));
    if (raw == null) return null;
    try {
      final wrapped = jsonDecode(raw) as Map<String, dynamic>;
      return wrapped['data'] as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Read cached primitive list (e.g. List<String>).
  Future<List<String>?> readStringList(String key) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(key));
    if (raw == null) return null;
    try {
      final wrapped = jsonDecode(raw) as Map<String, dynamic>;
      return (wrapped['data'] as List).cast<String>();
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    final prefs = await _prefs;
    await prefs.remove(_key(key));
  }

  Future<void> clearAll() async {
    final prefs = await _prefs;
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
