import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/localization_service.dart';
import '../services/business_service.dart';
import 'auth/login_screen.dart';
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

    final session = supabase.auth.currentSession;
    Widget destination = const LoginScreen();
    if (session != null) {
      try {
        await BusinessService()
            .ensureProfile(
              userId: session.user.id,
              email: session.user.email ?? '',
              fullName: session.user.userMetadata?['full_name'] as String?,
              avatarUrl: session.user.userMetadata?['avatar_url'] as String?,
            )
            .timeout(const Duration(seconds: 4));
        destination = const MainShell();
      } catch (_) {
        // A valid session should not be locked out by a temporary profile
        // lookup failure; the main app has its own retryable data states.
        destination = const MainShell();
      }
    }
    if (!mounted) return;

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
            // The logo is not square (800x600) and already has rounded
            // corners, so size it by width only and let the height follow.
            // Roughly matches the native splash shown just before this one.
            Image.asset(
              'assets/icon/app_icon.png',
              width: (MediaQuery.sizeOf(context).width * 0.6).clamp(160.0, 280.0),
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
