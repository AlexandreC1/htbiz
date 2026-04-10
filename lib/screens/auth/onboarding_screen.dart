import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../widgets/app_toast.dart';
import '../../services/business_service.dart';
import '../business/owner_dashboard_screen.dart';
import '../main_shell.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _isLoading = false;

  Future<void> _selectRole(String role) async {
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;

      if (user != null) {
        // User is already authenticated — save role and proceed
        await BusinessService().updateProfile(
          userId: user.id,
          email: user.email ?? '',
          role: role,
        );
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(
              page: role == 'business_owner'
                  ? const OwnerDashboardScreen()
                  : const MainShell(),
            ),
            (route) => false,
          );
        }
      } else {
        // User signed up but hasn't confirmed email yet
        // Save role locally so it's applied after first login
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_role', role);

        if (mounted) {
          AppToast.show(
            context,
            'Please check your email and confirm your account, then log in.',
            type: AppToastType.info,
            duration: const Duration(seconds: 5),
          );
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(page: const LoginScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.waving_hand_rounded,
                        size: 40,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome to HTBIZ!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'How will you use HTBIZ?',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Business Owner card
                    _RoleCard(
                      icon: Icons.storefront_rounded,
                      title: "I'm a Business Owner",
                      subtitle:
                          'List and manage your business, upload photos, respond to reviews',
                      color: AppColors.primaryDark,
                      onTap: () => _selectRole('business_owner'),
                    ),

                    const SizedBox(height: 16),

                    // Client card
                    _RoleCard(
                      icon: Icons.search_rounded,
                      title: "I'm a Client",
                      subtitle:
                          'Discover local businesses, read and write reviews',
                      color: AppColors.accent,
                      onTap: () => _selectRole('client'),
                    ),

                    const SizedBox(height: 48),
                    Text(
                      'You can change this later in your profile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}
