import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Lightweight connectivity watcher.
///
/// We avoid adding `connectivity_plus` for a minimal footprint: instead, we
/// poll the platform DNS resolver every [pollInterval]. When the status flips
/// from offline → online, [isOnline] notifies listeners so screens can refresh
/// their cached data automatically.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  static const Duration pollInterval = Duration(seconds: 8);
  static const String _probeHost = 'supabase.co';

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Timer? _timer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _check();
    _timer = Timer.periodic(pollInterval, (_) => _check());
  }

  Future<void> _check() async {
    final wasOnline = _isOnline;
    try {
      final result = await InternetAddress.lookup(_probeHost)
          .timeout(const Duration(seconds: 4));
      _isOnline = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      _isOnline = false;
    }
    if (wasOnline != _isOnline) {
      notifyListeners();
    }
  }

  /// Force an immediate connectivity probe (e.g. after a manual retry).
  Future<void> refresh() => _check();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
