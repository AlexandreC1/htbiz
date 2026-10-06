import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

/// Opt-in, best-effort first-party analytics. Never delays a user action.
class UsageAnalyticsService extends ChangeNotifier with WidgetsBindingObserver {
  UsageAnalyticsService._();
  static final instance = UsageAnalyticsService._();
  bool enabled = false;
  String? _userId;
  String _screen = 'home';
  Size _size = const Size(1, 1);
  DateTime? _started;
  Timer? _heartbeat;
  bool _sending = false;

  Future<void> initialize() async {
    _userId = supabase.auth.currentUser?.id;
    final prefs = await SharedPreferences.getInstance();
    enabled =
        _userId != null && (prefs.getBool('usage_consent_$_userId') ?? false);
    WidgetsBinding.instance.addObserver(this);
    supabase.auth.onAuthStateChange.listen((_) {
      final id = supabase.auth.currentUser?.id;
      if (id == _userId) return;
      enabled = false;
      _started = null;
      _userId = id;
      enabled = id != null && (prefs.getBool('usage_consent_$id') ?? false);
      notifyListeners();
    }, onError: (Object error) {
      debugPrint('Analytics auth update unavailable: $error');
    });
    _heartbeat =
        Timer.periodic(const Duration(minutes: 1), (_) => _flushTime());
  }

  Future<void> setEnabled(bool value) async {
    final id = supabase.auth.currentUser?.id;
    if (id == null) return;
    if (!value) {
      enabled = false;
      _started = null;
      notifyListeners();
    }
    await supabase.rpc('set_usage_consent', params: {'p_enabled': value});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('usage_consent_$id', value);
    enabled = value;
    _started = value ? DateTime.now() : null;
    notifyListeners();
    if (value) unawaited(record('screen_view'));
  }

  void screen(String name, Size size) {
    if (name == _screen && _started != null) {
      _size = size;
      return;
    }
    _flushTime();
    _screen = name;
    _size = size;
    _started = DateTime.now();
    unawaited(record('screen_view'));
  }

  void _flushTime() {
    final started = _started;
    if (started == null) return;
    final seconds = DateTime.now().difference(started).inSeconds.clamp(0, 3600);
    _started = DateTime.now();
    if (seconds > 0) unawaited(record('screen_time', seconds: seconds));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _started = DateTime.now();
    } else {
      _flushTime();
      _started = null;
    }
  }

  Future<void> record(String event,
      {int seconds = 0,
      String? media,
      double? latitude,
      double? longitude}) async {
    if (!enabled || _sending || supabase.auth.currentUser?.id != _userId) {
      return;
    }
    _sending = true;
    try {
      await supabase.rpc('record_usage', params: {
        'p_event': event,
        'p_screen': _screen,
        'p_os': kIsWeb
            ? 'web'
            : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
                .substring(
                    0,
                    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
                        .length
                        .clamp(0, 160)),
        'p_width': _size.width.round().clamp(1, 20000),
        'p_height': _size.height.round().clamp(1, 20000),
        'p_seconds': seconds,
        'p_media': media,
        'p_latitude': latitude,
        'p_longitude': longitude,
      }).timeout(const Duration(seconds: 5));
    } catch (_) {
      // No disk queue, retries, or failures in the app's critical path.
    } finally {
      _sending = false;
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
