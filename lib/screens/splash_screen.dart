import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_fonts/google_fonts.dart';
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

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Stage 1: Logo icon slides up + fades in
  late AnimationController _logoController;
  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _logoScale;

  // Stage 2: App name types in with shimmer
  late AnimationController _textController;
  late Animation<double> _titleFade;
  late Animation<double> _taglineFade;

  // Stage 3: Bottom loader bar
  late AnimationController _loaderController;

  // Stage 4: Exit — scale out
  late AnimationController _exitController;
  late Animation<double> _exitScale;
  late Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();

    // Logo animation — 800ms
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _logoFade = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOut,
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOutCubic,
    ));
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    // Text animation — 600ms, starts after logo
    _textController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _titleFade = CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _taglineFade = CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    // Loader bar — continuous
    _loaderController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Exit animation
    _exitController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _exitScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
    );

    // Remove native splash once Flutter UI is ready
    FlutterNativeSplash.remove();
    _startSequence();
  }

  Future<void> _startSequence() async {
    // Stage 1: Logo appears
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _logoController.forward();

    // Stage 2: Text fades in
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _textController.forward();

    // Stage 3: Loader starts
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _loaderController.repeat();

    // Wait for minimum splash duration
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    // Stage 4: Exit animation then navigate
    _loaderController.stop();
    await _exitController.forward();
    if (!mounted) return;

    _navigate();
  }

  Future<void> _navigate() async {
    // Check if the app was opened via a deep link (e.g. password reset)
    try {
      final appLinks = AppLinks();
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null &&
          initialLink.scheme == 'io.supabase.htbiz') {
        // Deep link detected — wait for Supabase to process the auth token
        // Listen for the passwordRecovery event with a timeout
        final completer = Completer<bool>();
        late StreamSubscription<AuthState> sub;
        sub = supabase.auth.onAuthStateChange.listen((data) {
          if (data.event == AuthChangeEvent.passwordRecovery) {
            if (!completer.isCompleted) completer.complete(true);
            sub.cancel();
          }
        });

        // Give Supabase up to 5 seconds to process the token
        final isRecovery = await completer.future
            .timeout(const Duration(seconds: 5), onTimeout: () => false);
        sub.cancel();

        if (isRecovery && mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const ResetPasswordScreen(),
              transitionDuration: const Duration(milliseconds: 500),
              transitionsBuilder: (_, animation, __, child) {
                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  ),
                  child: child,
                );
              },
            ),
          );
          return;
        }
      }
    } catch (_) {
      // If deep link check fails, continue with normal navigation
    }

    if (!mounted) return;

    final session = supabase.auth.currentSession;
    final destination =
        session != null ? const MainShell() : const LoginScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _loaderController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _exitController,
        builder: (context, child) => Opacity(
          opacity: _exitFade.value,
          child: Transform.scale(
            scale: _exitScale.value,
            child: child,
          ),
        ),
        child: Container(
          width: size.width,
          height: size.height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1B4F72), // Deep ocean blue (primary)
                Color(0xFF0E3A5C), // Darker blue (primaryDark)
                Color(0xFF00209F), // Haiti flag blue
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Subtle decorative circles
              Positioned(
                top: -size.width * 0.3,
                right: -size.width * 0.2,
                child: Container(
                  width: size.width * 0.7,
                  height: size.width * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Positioned(
                bottom: -size.width * 0.2,
                left: -size.width * 0.15,
                child: Container(
                  width: size.width * 0.5,
                  height: size.width * 0.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),

              // Main content
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated logo
                    SlideTransition(
                      position: _logoSlide,
                      child: FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                'assets/icon/app_icon.png',
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // App name
                    FadeTransition(
                      opacity: _titleFade,
                      child: Text(
                        localization.t('app_name'),
                        style: GoogleFonts.poppins(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 3,
                          height: 1.1,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Tagline
                    FadeTransition(
                      opacity: _taglineFade,
                      child: Text(
                        localization.t('app_tagline'),
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.8),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Animated loader
                    FadeTransition(
                      opacity: _taglineFade,
                      child: SizedBox(
                        width: 140,
                        child: AnimatedBuilder(
                          animation: _loaderController,
                          builder: (context, _) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: _loaderController.isAnimating
                                    ? null
                                    : 0,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withValues(alpha: 0.8),
                                ),
                                minHeight: 3,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Version at bottom
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 24,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _taglineFade,
                  child: Text(
                    'v1.0.0',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
