import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/splash_screen.dart';
import 'services/connectivity_service.dart';
import 'services/localization_service.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Anything thrown during startup used to escape main(), leaving the native
  // splash on screen forever with no error and no way forward. Every step
  // below is now either recoverable or ends on a screen that says why.
  try {
    await dotenv.load(fileName: '.env');
  } catch (error) {
    debugPrint('Could not read .env: $error');
  }

  if (SupabaseConfig.supabaseUrl.isEmpty ||
      SupabaseConfig.supabaseAnonKey.isEmpty) {
    FlutterNativeSplash.remove();
    runApp(const _StartupFailureApp(
      reason: 'The app is missing its Supabase configuration.',
      detail:
          'SUPABASE_URL and SUPABASE_ANON_KEY were not found in the bundled '
          '.env file. This build cannot reach the server.',
    ));
    return;
  }

  // Push notifications are a nice-to-have. A device with no Play Services, or
  // a build whose google-services.json is stale, must still open the app.
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    firebaseReady = true;
  } catch (error) {
    debugPrint('Firebase unavailable, push notifications disabled: $error');
  }

  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  } catch (error) {
    FlutterNativeSplash.remove();
    runApp(_StartupFailureApp(
      reason: 'The app could not start.',
      detail: 'Failed to connect to the server: $error',
    ));
    return;
  }

  // A corrupt SharedPreferences entry should not be fatal — the app falls back
  // to its default language.
  try {
    await LocalizationService().init();
  } catch (error) {
    debugPrint('Localization failed to initialise: $error');
  }

  ConnectivityService.instance.start();

  // Framework errors that reach the top level: log them rather than letting a
  // release build show a grey screen with no trace.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Uncaught framework error: ${details.exception}');
  };

  runApp(
    ChangeNotifierProvider(
      create: (_) => LocalizationService(),
      child: const HTBizApp(),
    ),
  );
}

/// Whether Firebase came up. Guards every FCM call so a failed init cannot
/// crash a screen later.
bool firebaseReady = false;

/// Shown when the app cannot start at all. Better than a frozen splash.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.reason, required this.detail});

  final String reason;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0E3A5C),
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 20),
              Text(
                reason,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                detail,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final supabase = Supabase.instance.client;
final navigatorKey = GlobalKey<NavigatorState>();

// Brand colors — Haiti-inspired Caribbean palette
class AppColors {
  static const primary = Color(0xFF1B4F72); // Deep ocean blue
  static const primaryDark = Color(0xFF0E3A5C); // Darker blue
  static const primaryLight = Color(0xFFD4E6F1); // Soft sky blue
  static const accent = Color(0xFFE8A838); // Warm golden amber
  static const surface = Color(0xFFFAF8F5); // Warm off-white
  static const card = Colors.white;
  static const textPrimary = Color(0xFF1C2833);
  static const textSecondary = Color(0xFF6C7A89);
  static const divider = Color(0xFFE8E4DF); // Warm gray divider
}

class HTBizApp extends StatefulWidget {
  const HTBizApp({super.key});

  @override
  State<HTBizApp> createState() => _HTBizAppState();
}

class _HTBizAppState extends State<HTBizApp> {
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = supabase.auth.onAuthStateChange.listen(
      _onAuthStateChange,
      // An error on this stream used to cancel the subscription outright, so
      // password-recovery links stopped working until a cold restart. A failed
      // token refresh also arrives here rather than as an event.
      onError: (Object error) {
        debugPrint('Auth stream error: $error');
        if (error is AuthException) _goToLogin();
      },
      cancelOnError: false,
    );
  }

  void _onAuthStateChange(AuthState data) {
    switch (data.event) {
      case AuthChangeEvent.passwordRecovery:
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          (route) => false,
        );

      case AuthChangeEvent.signedOut:
        // The refresh token expired or was revoked. Nothing past this point
        // works without a session, so send the user to the login screen rather
        // than leaving them on a screen whose every request 401s.
        _goToLogin();

      default:
        break;
    }
  }

  void _goToLogin() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'HTBIZ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.surface,
        textTheme: GoogleFonts.poppinsTextTheme(),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          clipBehavior: Clip.antiAlias,
          color: AppColors.card,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            side: const BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: Colors.grey.shade300),
          selectedColor: AppColors.primaryLight,
          showCheckmark: false,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 1,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

/// Smooth fade + slide page transition
class FadeSlideRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadeSlideRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.04),
                  end: Offset.zero,
                ).animate(curve),
                child: child,
              ),
            );
          },
        );
}
