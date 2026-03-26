import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/user_profile.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import '../auth/login_screen.dart';
import '../business/analytics_dashboard_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _businessService = BusinessService();
  final _nameController = TextEditingController();
  UserProfile? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;
  File? _selectedAvatar;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    final newName = _nameController.text.trim();
    final savedName = _profile?.fullName ?? '';
    final changed = newName != savedName;
    if (changed != _hasChanges && _selectedAvatar == null) {
      setState(() => _hasChanges = changed);
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final user = supabase.auth.currentUser;
    if (user != null && !(user.isAnonymous)) {
      final profile = await _businessService.getProfile(user.id);
      setState(() {
        _profile = profile;
        _nameController.text = profile?.fullName ?? '';
        _isLoading = false;
        _hasChanges = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final localization =
        Provider.of<LocalizationService>(context, listen: false);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(localization.t('choose_from_gallery')),
              onTap: () async {
                Navigator.pop(context);
                final image = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 512,
                  maxHeight: 512,
                  imageQuality: 85,
                );
                if (image != null) {
                  setState(() {
                    _selectedAvatar = File(image.path);
                    _hasChanges = true;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(localization.t('take_photo')),
              onTap: () async {
                Navigator.pop(context);
                final image = await ImagePicker().pickImage(
                  source: ImageSource.camera,
                  maxWidth: 512,
                  maxHeight: 512,
                  imageQuality: 85,
                );
                if (image != null) {
                  setState(() {
                    _selectedAvatar = File(image.path);
                    _hasChanges = true;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    setState(() => _isSaving = true);
    try {
      String? avatarUrl = _profile?.avatarUrl;
      if (_selectedAvatar != null) {
        avatarUrl = await _businessService.uploadAvatarImage(_selectedAvatar!);
      }
      await _businessService.updateProfile(
        userId: user.id,
        email: user.email ?? '',
        fullName: _nameController.text.trim(),
        avatarUrl: avatarUrl,
        role: _profile?.role,
      );
      setState(() {
        _selectedAvatar = null;
        _hasChanges = false;
      });
      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _changeRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final currentRole = _profile?.role ?? 'client';
    final newRole =
        currentRole == 'business_owner' ? 'client' : 'business_owner';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Role'),
        content: Text(
          newRole == 'business_owner'
              ? 'Switch to Business Owner? You will be able to list and manage businesses.'
              : 'Switch to Client? You will no longer be able to add businesses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isSaving = true);
      try {
        await _businessService.updateProfile(
          userId: user.id,
          email: user.email ?? '',
          role: newRole,
        );
        await _loadProfile();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final localization = Provider.of<LocalizationService>(context);
    final isGuest = user?.isAnonymous ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('profile')),
        actions: [
          if (!isGuest && !_isLoading && (_hasChanges || _isSaving))
            TextButton(
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF006064),
                      ),
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 24),

                // Avatar
                Center(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: isGuest ? null : _pickAvatar,
                        child: CircleAvatar(
                          radius: 56,
                          backgroundColor: Colors.teal,
                          backgroundImage: _selectedAvatar != null
                              ? FileImage(_selectedAvatar!)
                              : (_profile?.avatarUrl != null
                                  ? NetworkImage(_profile!.avatarUrl!)
                                      as ImageProvider
                                  : null),
                          child: (_selectedAvatar == null &&
                                  _profile?.avatarUrl == null)
                              ? Text(
                                  (user?.email?.substring(0, 1) ?? 'G')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 40,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      if (!isGuest)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF006064),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Email
                Center(
                  child: Text(
                    user?.email ?? localization.t('continue_as_guest'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),

                // Role badge
                if (!isGuest && _profile != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: GestureDetector(
                      onTap: _changeRole,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: _profile!.isBusinessOwner
                              ? Colors.teal[50]
                              : Colors.blue[50],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _profile!.isBusinessOwner
                                ? Colors.teal
                                : Colors.blue,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _profile!.isBusinessOwner
                                  ? Icons.store
                                  : Icons.person,
                              size: 16,
                              color: _profile!.isBusinessOwner
                                  ? Colors.teal[700]
                                  : Colors.blue[700],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _profile!.isBusinessOwner
                                  ? 'Business Owner'
                                  : 'Client',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _profile!.isBusinessOwner
                                    ? Colors.teal[700]
                                    : Colors.blue[700],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit,
                              size: 12,
                              color: _profile!.isBusinessOwner
                                  ? Colors.teal[400]
                                  : Colors.blue[400],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                const Divider(),

                // Full name field (only for authenticated users)
                if (!isGuest) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        hintText: 'Enter your full name',
                      ),
                    ),
                  ),
                  const Divider(),
                ],

                // Analytics (business owners only)
                if (!isGuest && (_profile?.isBusinessOwner ?? false)) ...[
                  ListTile(
                    leading: const Icon(Icons.analytics, color: Colors.teal),
                    title: Text(localization.t('analytics')),
                    subtitle: Text(localization.t('dashboard')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const AnalyticsDashboardScreen()),
                      );
                    },
                  ),
                  const Divider(),
                ],

                // Language Selection
                ListTile(
                  leading: const Icon(Icons.language, color: Colors.teal),
                  title: Text(localization.t('language')),
                  subtitle: Text(_getLanguageName(localization.currentLanguage)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _showLanguageDialog(context),
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
                    await supabase.auth.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ],
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
      leading: Text(flag, style: const TextStyle(fontSize: 32)),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.teal : null,
        ),
      ),
      trailing:
          isSelected ? const Icon(Icons.check_circle, color: Colors.teal) : null,
      onTap: onTap,
    );
  }
}
