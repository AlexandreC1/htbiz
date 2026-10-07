import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../widgets/app_toast.dart';
import '../../services/localization_service.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _passwordReset = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final loc = Provider.of<LocalizationService>(context, listen: false);

    try {
      await supabase.auth.updateUser(
        UserAttributes(
          password: _passwordController.text,
        ),
      );

      if (mounted) {
        setState(() {
          _passwordReset = true;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);

        String errorMessage = loc.t('error_occurred');

        if (error.toString().contains('expired')) {
          errorMessage = loc.t('link_expired_error');
        } else if (error.toString().contains('same')) {
          errorMessage = loc.t('password_must_differ');
        }

        AppToast.error(context, errorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = Provider.of<LocalizationService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('reset_password')),
        automaticallyImplyLeading: !_passwordReset,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child:
                _passwordReset ? _buildSuccessView(loc) : _buildFormView(loc),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(LocalizationService loc) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.vpn_key,
            size: 80,
            color: AppColors.primary,
          ),
          const SizedBox(height: 30),
          Text(
            loc.t('create_new_password'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            loc.t('new_password_description'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 40),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: loc.t('password_hint'),
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return loc.t('please_enter_password');
              }
              if (value.length < 8) {
                return loc.t('password_min_length');
              }
              if (!RegExp(r'(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(value)) {
                return loc.t('password_complexity');
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              hintText: loc.t('confirm_password'),
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () {
                  setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword);
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return loc.t('please_confirm_password');
              }
              if (value != _passwordController.text) {
                return loc.t('passwords_dont_match');
              }
              return null;
            },
          ),
          const SizedBox(height: 30),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isLoading
                ? const SizedBox(
                    height: 52,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                : SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _resetPassword,
                      child: Text(loc.t('reset_password')),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(LocalizationService loc) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.green[50],
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle,
            size: 80,
            color: Colors.green[600],
          ),
        ),
        const SizedBox(height: 30),
        Text(
          loc.t('password_reset_success'),
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.green[700],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            loc.t('password_reset_success_message'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 15),
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                FadeSlideRoute(page: const LoginScreen()),
                (route) => false,
              );
            },
            child: Text(loc.t('sign_in')),
          ),
        ),
      ],
    );
  }
}
