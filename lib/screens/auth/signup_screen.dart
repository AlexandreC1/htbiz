import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../services/app_exception.dart';
import '../../services/google_auth_service.dart';
import '../../widgets/app_toast.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import '../main_shell.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.returnToReview = false});

  final bool returnToReview;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _awaitingEmailConfirmation = false;
  bool _isResendingConfirmation = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn &&
          _awaitingEmailConfirmation &&
          mounted) {
        _continueToApp();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      if (kIsWeb) {
        await supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Uri.base.resolve('/').toString(),
        );
        return;
      }
      final googleUser = await GoogleAuthService.authenticate();

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
        if (user != null) {
          await BusinessService().ensureProfile(
            userId: user.id,
            email: user.email ?? '',
            fullName: user.userMetadata?['full_name'] as String?,
            avatarUrl: user.userMetadata?['avatar_url'] as String?,
          );
        }
        if (mounted && widget.returnToReview) {
          Navigator.of(context).pop(true);
        } else if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(page: const MainShell()),
            (route) => false,
          );
        }
      }
    } catch (error) {
      debugPrint('Google sign-up failed: $error');
      if (error is GoogleSignInException &&
          error.code == GoogleSignInExceptionCode.canceled) {
        return;
      }
      if (mounted) {
        AppToast.error(context, AppException.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        emailRedirectTo: kIsWeb
            ? Uri.base.resolve('/').toString()
            : 'io.supabase.htbiz://login-callback/',
      );

      if (!mounted) return;
      if (response.session != null) {
        await _continueToApp();
      } else {
        setState(() => _awaitingEmailConfirmation = true);
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(context, AppException.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _continueToApp() async {
    if (!mounted) return;
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await BusinessService().ensureProfile(
          userId: user.id,
          email: user.email ?? '',
          fullName: user.userMetadata?['full_name'] as String?,
          avatarUrl: user.userMetadata?['avatar_url'] as String?,
        );
      } catch (error) {
        if (!mounted) return;
        AppToast.error(context, AppException.from(error).message);
        return;
      }
    }
    if (!mounted) return;
    if (widget.returnToReview) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(page: const MainShell()),
      (route) => false,
    );
  }

  Future<void> _resendConfirmation() async {
    setState(() => _isResendingConfirmation = true);
    final loc = Provider.of<LocalizationService>(context, listen: false);
    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: _emailController.text.trim(),
        emailRedirectTo: kIsWeb
            ? Uri.base.resolve('/').toString()
            : 'io.supabase.htbiz://login-callback/',
      );
      if (mounted) {
        AppToast.show(
          context,
          loc.t('verification_resent'),
          type: AppToastType.success,
        );
      }
    } catch (error) {
      if (mounted) AppToast.error(context, AppException.from(error).message);
    } finally {
      if (mounted) setState(() => _isResendingConfirmation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('create_account')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding + 24),
          child: _awaitingEmailConfirmation
              ? _EmailConfirmationNotice(
                  email: _emailController.text.trim(),
                  isResending: _isResendingConfirmation,
                  onResend: _resendConfirmation,
                  onBack: () =>
                      setState(() => _awaitingEmailConfirmation = false),
                  localization: localization,
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.person_add_outlined,
                            size: 36,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        localization.t('join_htbiz'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),

                      const SizedBox(height: 36),

                      // Email
                      _FieldLabel(text: localization.t('email')),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: 'you@example.com',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon:
                              const Icon(Icons.email_outlined, size: 20),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return localization.t('please_enter_email');
                          }
                          if (!value.contains('@')) {
                            return localization.t('please_enter_valid_email');
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Password
                      _FieldLabel(text: localization.t('password')),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: '********',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon:
                              const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(
                                  () => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return localization.t('please_enter_password');
                          }
                          if (value.length < 8) {
                            return localization.t('password_min_length');
                          }
                          if (!RegExp(r'(?=.*[a-z])(?=.*[A-Z])(?=.*\d)')
                              .hasMatch(value)) {
                            return localization.t('password_complexity');
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Confirm Password
                      _FieldLabel(text: localization.t('confirm_password')),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _signUp(),
                        decoration: InputDecoration(
                          hintText: '********',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon:
                              const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() => _obscureConfirmPassword =
                                  !_obscureConfirmPassword);
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return localization.t('please_confirm_password');
                          }
                          if (value != _passwordController.text) {
                            return localization.t('passwords_dont_match');
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 32),

                      // Sign up button
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
                                  onPressed: _signUp,
                                  child: Text(localization.t('create_account')),
                                ),
                              ),
                      ),

                      const SizedBox(height: 16),

                      // Divider
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
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

                      // Google Sign Up button
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: (_isLoading || _isGoogleLoading)
                              ? null
                              : _signUpWithGoogle,
                          icon: _isGoogleLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.g_mobiledata, size: 28),
                          label: Text(
                            localization.t('continue_with_google'),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: BorderSide(color: Colors.grey.shade300),
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

class _EmailConfirmationNotice extends StatelessWidget {
  const _EmailConfirmationNotice({
    required this.email,
    required this.isResending,
    required this.onResend,
    required this.onBack,
    required this.localization,
  });

  final String email;
  final bool isResending;
  final VoidCallback onResend;
  final VoidCallback onBack;
  final LocalizationService localization;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 48),
          const Icon(
            Icons.mark_email_read_outlined,
            size: 72,
            color: AppColors.primary,
          ),
          const SizedBox(height: 24),
          Text(
            localization.t('verify_your_email'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            localization.t('verification_sent_to'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            localization.t('verification_continue'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: isResending ? null : onResend,
              icon: isResending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_email_unread_outlined),
              label: Text(localization.t('resend_verification')),
            ),
          ),
          TextButton(
            onPressed: onBack,
            child: Text(localization.t('use_different_email')),
          ),
        ],
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  }
}
