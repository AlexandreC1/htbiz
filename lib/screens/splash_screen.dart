import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import '../main.dart';
import '../services/localization_service.dart';
import 'auth/login_screen.dart';
import 'auth/reset_password_screen.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    try {
      final appLinks = AppLinks();
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null && initialLink.scheme == 'io.supabase.htbiz') {
        final completer = Completer<bool>();
        late StreamSubscription<AuthState> sub;
        sub = supabase.auth.onAuthStateChange.listen((data) {
          if (data.event == AuthChangeEvent.passwordRecovery) {
            if (!completer.isCompleted) completer.complete(true);
            sub.cancel();
          }
        });

        final isRecovery = await completer.future
            .timeout(const Duration(seconds: 5), onTimeout: () => false);
        sub.cancel();

        if (isRecovery && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const ResetPasswordScreen(),
            ),
          );
          return;
        }
      }
    } catch (_) {}

    if (!mounted) return;

    final session = supabase.auth.currentSession;
    final destination =
        session != null ? const MainShell() : const LoginScreen();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0E3A5C),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 120,
                height: 120,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              localization.t('app_name'),
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
