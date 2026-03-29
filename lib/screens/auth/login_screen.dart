import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import '../business/owner_dashboard_screen.dart';
import '../home/home_screen.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Too many attempts. Try again in ${seconds}s'),
          backgroundColor: Colors.orange,
        ),
      );
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
                    : const HomeScreen(),
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
              FadeSlideRoute(page: const HomeScreen()),
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInAsGuest() async {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        FadeSlideRoute(page: const HomeScreen()),
      );
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
                          Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                size: 40,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
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
