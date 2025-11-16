import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../main.dart';
import '../../services/localization_service.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  String? _avatarUrl;
  Map<String, dynamic> _userStats = {
    'businesses': 0,
    'reviews': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = supabase.auth.currentUser;
    if (user == null || (user.isAnonymous ?? true)) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Load user statistics
      final businessCount = await supabase
          .from('businesses')
          .select('id')
          .eq('owner_id', user.id)
          .count();

      final reviewCount = await supabase
          .from('reviews')
          .select('id')
          .eq('user_id', user.id)
          .count();

      setState(() {
        _userStats = {
          'businesses': businessCount.count,
          'reviews': reviewCount.count,
        };
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile data: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = supabase.auth.currentUser;
    if (user == null || (user.isAnonymous ?? true)) {
      _showAuthRequiredDialog();
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _isLoading = true;
      });

      // Upload to Supabase Storage
      final String filePath = 'avatars/${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File file = File(image.path);

      await supabase.storage.from('avatars').upload(
            filePath,
            file,
            fileOptions: const FileOptions(upsert: true),
          );

      final String publicUrl = supabase.storage.from('avatars').getPublicUrl(filePath);

      setState(() {
        _avatarUrl = publicUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avatar updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading avatar: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAuthRequiredDialog() {
    final localization = Provider.of<LocalizationService>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign In Required'),
        content: const Text(
          'Please sign in with an account to access this feature. Guest users have limited functionality.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localization.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final localization = Provider.of<LocalizationService>(context);
    final isGuest = user == null || (user.isAnonymous ?? true);

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('profile')),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUserData,
              child: ListView(
                children: [
                  // Header Section with gradient
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).primaryColor.withOpacity(0.8),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        // Avatar with edit button
                        Stack(
                          children: [
                            GestureDetector(
                              onTap: isGuest ? null : _pickAndUploadAvatar,
                              child: Hero(
                                tag: 'profile_avatar',
                                child: CircleAvatar(
                                  radius: 60,
                                  backgroundColor: Colors.white,
                                  backgroundImage: _avatarUrl != null
                                      ? CachedNetworkImageProvider(_avatarUrl!)
                                      : null,
                                  child: _avatarUrl == null
                                      ? Text(
                                          user?.email?.substring(0, 1).toUpperCase() ?? 'G',
                                          style: const TextStyle(
                                            fontSize: 48,
                                            color: Colors.teal,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            if (!isGuest)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: _pickAndUploadAvatar,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.teal,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // User info
                        Text(
                          user?.email ?? localization.t('continue_as_guest'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (isGuest)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Guest User',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Statistics Section (only for authenticated users)
                  if (!isGuest) ...[
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              icon: Icons.business,
                              label: 'Businesses',
                              value: _userStats['businesses'].toString(),
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _StatCard(
                              icon: Icons.rate_review,
                              label: 'Reviews',
                              value: _userStats['reviews'].toString(),
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],

                  // Guest user sign-in prompt
                  if (isGuest) ...[
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.orange.shade700,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Limited Features',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Sign in to access all features including adding businesses, uploading photos, and more!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.login),
                                label: const Text('Sign In'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                  ],

                  // Profile Options
                  const SizedBox(height: 8),

                  // My Businesses (only for authenticated users)
                  if (!isGuest)
                    ListTile(
                      leading: const Icon(Icons.business, color: Colors.teal),
                      title: const Text('My Businesses'),
                      subtitle: Text('${_userStats['businesses']} businesses'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        // TODO: Navigate to my businesses page
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('My Businesses page coming soon!'),
                          ),
                        );
                      },
                    ),

                  // My Reviews (only for authenticated users)
                  if (!isGuest)
                    ListTile(
                      leading: const Icon(Icons.rate_review, color: Colors.blue),
                      title: const Text('My Reviews'),
                      subtitle: Text('${_userStats['reviews']} reviews'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        // TODO: Navigate to my reviews page
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('My Reviews page coming soon!'),
                          ),
                        );
                      },
                    ),

                  // Favorites (only for authenticated users)
                  if (!isGuest)
                    ListTile(
                      leading: const Icon(Icons.favorite, color: Colors.red),
                      title: const Text('Saved Businesses'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        // TODO: Navigate to saved businesses page
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Saved Businesses coming soon!'),
                          ),
                        );
                      },
                    ),

                  if (!isGuest) const Divider(),

                  // Language Selection
                  ListTile(
                    leading: const Icon(Icons.language, color: Colors.teal),
                    title: Text(localization.t('language')),
                    subtitle: Text(_getLanguageName(localization.currentLanguage)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showLanguageDialog(context),
                  ),

                  // Settings
                  ListTile(
                    leading: const Icon(Icons.settings, color: Colors.grey),
                    title: const Text('Settings'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Settings page coming soon!'),
                        ),
                      );
                    },
                  ),

                  // Help & Support
                  ListTile(
                    leading: const Icon(Icons.help_outline, color: Colors.grey),
                    title: const Text('Help & Support'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Help & Support page coming soon!'),
                        ),
                      );
                    },
                  ),

                  const Divider(),

                  // Logout
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: Text(
                      localization.t('logout'),
                      style: const TextStyle(color: Colors.red),
                    ),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Confirm Logout'),
                          content: const Text('Are you sure you want to logout?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(localization.t('cancel')),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Logout'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true && mounted) {
                        await supabase.auth.signOut();
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      }
                    },
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'fr':
        return 'Français';
      case 'ht':
        return 'Kreyòl Ayisyen';
      default:
        return 'English';
    }
  }

  void _showLanguageDialog(BuildContext context) {
    final localization =
        Provider.of<LocalizationService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.t('select_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LanguageOption(
              code: 'en',
              name: 'English',
              flag: '🇺🇸',
              currentLanguage: localization.currentLanguage,
              onTap: () {
                localization.setLanguage('en');
                Navigator.pop(context);
              },
            ),
            _LanguageOption(
              code: 'fr',
              name: 'Français',
              flag: '🇫🇷',
              currentLanguage: localization.currentLanguage,
              onTap: () {
                localization.setLanguage('fr');
                Navigator.pop(context);
              },
            ),
            _LanguageOption(
              code: 'ht',
              name: 'Kreyòl Ayisyen',
              flag: '🇭🇹',
              currentLanguage: localization.currentLanguage,
              onTap: () {
                localization.setLanguage('ht');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String code;
  final String name;
  final String flag;
  final String currentLanguage;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.code,
    required this.name,
    required this.flag,
    required this.currentLanguage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = code == currentLanguage;

    return ListTile(
      leading: Text(
        flag,
        style: const TextStyle(fontSize: 32),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.teal : null,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.teal)
          : null,
      onTap: onTap,
    );
  }
}
