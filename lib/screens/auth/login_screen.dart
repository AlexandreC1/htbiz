import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/htbiz_logo.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import '../business/owner_dashboard_screen.dart';
import '../main_shell.dart';
import 'onboarding_screen.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    ));
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    // Throttle after repeated failures
    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      final seconds = _lockoutUntil!.difference(DateTime.now()).inSeconds;
      AppToast.warning(context, 'Too many attempts. Try again in ${seconds}s');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        // Check for pending role from onboarding
        final prefs = await SharedPreferences.getInstance();
        final pendingRole = prefs.getString('pending_role');
        final user = supabase.auth.currentUser;

        if (pendingRole != null && user != null) {
          await prefs.remove('pending_role');
          await BusinessService().updateProfile(
            userId: user.id,
            email: user.email ?? '',
            role: pendingRole,
          );

          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              FadeSlideRoute(
                page: pendingRole == 'business_owner'
                    ? const OwnerDashboardScreen()
                    : const MainShell(),
              ),
              (route) => false,
            );
          }
        } else if (mounted) {
          final profile = user != null
              ? await BusinessService().getProfile(user.id)
              : null;

          if (profile == null && mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              FadeSlideRoute(page: const OnboardingScreen()),
              (route) => false,
            );
          } else if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              FadeSlideRoute(page: const MainShell()),
              (route) => false,
            );
          }
        }
      }
    } catch (error) {
      _failedAttempts++;
      if (_failedAttempts >= 5) {
        final lockSeconds = _failedAttempts >= 10
            ? 120
            : _failedAttempts >= 8
                ? 60
                : 30;
        _lockoutUntil = DateTime.now().add(Duration(seconds: lockSeconds));
      }

      if (mounted) {
        String errorMessage = 'An error occurred';

        if (error.toString().contains('invalid_credentials')) {
          errorMessage = 'Invalid email or password';
        } else if (error.toString().contains('Email not confirmed')) {
          errorMessage = 'Please verify your email first';
        }

        AppToast.error(context, errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInAsGuest() async {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        FadeSlideRoute(page: const MainShell()),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      const webClientId =
          '85584991269-f04tu8dt4pn7vhn4ipijtaqocmb613qh.apps.googleusercontent.com';

      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(serverClientId: webClientId);
      final googleUser = await googleSignIn.authenticate();

      final idToken = googleUser.authentication.idToken;

      if (idToken == null) {
        throw Exception('No ID token received from Google');
      }

      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      if (mounted) {
        final user = supabase.auth.currentUser;
        final profile = user != null
            ? await BusinessService().getProfile(user.id)
            : null;

        if (profile == null && mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(page: const OnboardingScreen()),
            (route) => false,
          );
        } else if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(page: const MainShell()),
            (route) => false,
          );
        }
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(context, 'Google sign-in failed: $error');
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        24, 48, 24, bottomPadding + 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header section
                          const Center(child: HTBizLogo(size: 84)),
                          const SizedBox(height: 24),
                          Text(
                            localization.t('welcome'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            localization.t('sign_in_to_continue'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              color: AppColors.textSecondary,
                            ),
                          ),

                          const SizedBox(height: 40),

                          // Email field
                          Text(
                            localization.t('email'),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: 'you@example.com',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              prefixIcon: const Icon(
                                Icons.email_outlined,
                                size: 20,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return localization
                                    .t('please_enter_email');
                              }
                              if (!value.contains('@')) {
                                return localization
                                    .t('please_enter_valid_email');
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // Password field
                          Text(
                            localization.t('password'),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _signIn(),
                            decoration: InputDecoration(
                              hintText: '********',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() =>
                                      _obscurePassword = !_obscurePassword);
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return localization
                                    .t('please_enter_password');
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 4),

                          // Forgot password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  FadeSlideRoute(
                                    page: const ForgotPasswordScreen(),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                              ),
                              child: Text(
                                'Mot de passe oubli\u00e9?',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Sign In button
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 52,
                                    child: Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                    ),
                                  )
                                : SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _signIn,
                                      child: Text(
                                          localization.t('sign_in')),
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 16),

                          // Divider
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                child: Text(
                                  localization.t('or'),
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Google Sign In button
                          SizedBox(
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed:
                                  (_isLoading || _isGoogleLoading)
                                      ? null
                                      : _signInWithGoogle,
                              icon: _isGoogleLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Image.network(
                                      'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                      width: 20,
                                      height: 20,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(Icons.g_mobiledata,
                                                  size: 24),
                                    ),
                              label: Text(
                                localization.t('continue_with_google'),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Guest button
                          SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : _signInAsGuest,
                              child: Text(
                                  localization.t('continue_as_guest')),
                            ),
                          ),

                          const Spacer(),

                          // Sign up link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                localization.t('dont_have_account'),
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    FadeSlideRoute(
                                      page: const SignUpScreen(),
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                ),
                                child: Text(
                                  localization.t('sign_up'),
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
