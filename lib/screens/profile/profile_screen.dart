import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../widgets/app_toast.dart';
import '../../models/user_profile.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import '../auth/login_screen.dart';
import '../main_shell.dart';

class ProfileScreen extends StatefulWidget {
  final MainShellState? shell;
  const ProfileScreen({super.key, this.shell});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _businessService = BusinessService();
  final _nameController = TextEditingController();
  UserProfile? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditingName = false;
  File? _selectedAvatar;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
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
        _isEditingName = false;
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
                  setState(() => _selectedAvatar = File(image.path));
                  _saveAvatar();
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
                  setState(() => _selectedAvatar = File(image.path));
                  _saveAvatar();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAvatar() async {
    final user = supabase.auth.currentUser;
    if (user == null || _selectedAvatar == null) return;
    setState(() => _isSaving = true);
    try {
      final avatarUrl =
          await _businessService.uploadAvatarImage(_selectedAvatar!);
      await _businessService.updateProfile(
        userId: user.id,
        email: user.email ?? '',
        fullName: _profile?.fullName,
        avatarUrl: avatarUrl,
        role: _profile?.role,
      );
      setState(() => _selectedAvatar = null);
      await _loadProfile();
      if (mounted) {
        AppToast.success(context, 'Photo updated');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveName() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await _businessService.updateProfile(
        userId: user.id,
        email: user.email ?? '',
        fullName: newName,
        role: _profile?.role,
      );
      await _loadProfile();
      widget.shell?.refreshProfile();
      if (mounted) {
        AppToast.success(context, 'Name updated');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
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
    final localization =
        Provider.of<LocalizationService>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.t('change_role')),
        content: Text(
          newRole == 'business_owner'
              ? localization.t('switch_to_owner_desc')
              : localization.t('switch_to_client_desc'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localization.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localization.t('confirm')),
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
        widget.shell?.refreshProfile();
      } catch (e) {
        if (mounted) {
          AppToast.error(context, 'Error: $e');
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
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                // Profile header card
                _buildProfileHeader(user, isGuest, localization),

                const SizedBox(height: 24),

                // Account section
                if (!isGuest) ...[
                  _buildSectionHeader(localization.t('account')),
                  _buildNameTile(localization),
                  _buildRoleTile(localization),
                  const SizedBox(height: 16),
                ],

                // Settings section
                _buildSectionHeader(localization.t('settings')),
                _buildLanguageTile(localization),

                const SizedBox(height: 16),

                // Logout
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await supabase.auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          FadeSlideRoute(page: const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: Text(
                      localization.t('logout'),
                      style: const TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildProfileHeader(
      dynamic user, bool isGuest, LocalizationService localization) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar
          Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                backgroundImage: _selectedAvatar != null
                    ? FileImage(_selectedAvatar!)
                    : (_profile?.avatarUrl != null
                        ? NetworkImage(_profile!.avatarUrl!) as ImageProvider
                        : null),
                child:
                    (_selectedAvatar == null && _profile?.avatarUrl == null)
                        ? Text(
                            (_profile?.fullName?.substring(0, 1) ??
                                    user?.email?.substring(0, 1) ??
                                    'G')
                                .toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 36,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
              ),
              if (!isGuest)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _isSaving ? null : _pickAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        color: AppColors.primary,
                        size: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Name
          Text(
            _profile?.fullName ?? user?.email ?? localization.t('guest'),
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),

          if (user?.email != null) ...[
            const SizedBox(height: 4),
            Text(
              user!.email!,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],

          if (!isGuest && _profile != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _profile!.isBusinessOwner ? Icons.store : Icons.person,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _profile!.isBusinessOwner
                        ? localization.t('business_owner')
                        : localization.t('client'),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_isSaving) ...[
            const SizedBox(height: 12),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildNameTile(LocalizationService localization) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: _isEditingName
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: localization.t('enter_full_name'),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      style: GoogleFonts.poppins(fontSize: 15),
                      maxLength: 100,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      onSubmitted: (_) {
                        _saveName();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      setState(() {
                        _isEditingName = false;
                        _nameController.text = _profile?.fullName ?? '';
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.check, size: 20, color: AppColors.primary),
                    onPressed: _saveName,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            )
          : ListTile(
              leading: const Icon(Icons.person_outline, color: AppColors.primary),
              title: Text(
                localization.t('full_name'),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
              subtitle: Text(
                _profile?.fullName ?? localization.t('not_set'),
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => setState(() => _isEditingName = true),
              ),
            ),
    );
  }

  Widget _buildRoleTile(LocalizationService localization) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Icon(
          _profile?.isBusinessOwner == true ? Icons.store : Icons.person,
          color: AppColors.primary,
        ),
        title: Text(
          localization.t('account_type'),
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        subtitle: Text(
          _profile?.isBusinessOwner == true
              ? localization.t('business_owner')
              : localization.t('client'),
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: TextButton(
          onPressed: _changeRole,
          child: Text(
            localization.t('switch'),
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile(LocalizationService localization) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: const Icon(Icons.language, color: AppColors.primary),
        title: Text(
          localization.t('language'),
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        subtitle: Text(
          _getLanguageName(localization.currentLanguage),
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _showLanguageDialog(context),
      ),
    );
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'fr':
        return 'Fran\u00e7ais';
      case 'ht':
        return 'Krey\u00f2l Ayisyen';
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
              flag: '\ud83c\uddfa\ud83c\uddf8',
              currentLanguage: localization.currentLanguage,
              onTap: () {
                localization.setLanguage('en');
                Navigator.pop(context);
              },
            ),
            _LanguageOption(
              code: 'fr',
              name: 'Fran\u00e7ais',
              flag: '\ud83c\uddeb\ud83c\uddf7',
              currentLanguage: localization.currentLanguage,
              onTap: () {
                localization.setLanguage('fr');
                Navigator.pop(context);
              },
            ),
            _LanguageOption(
              code: 'ht',
              name: 'Krey\u00f2l Ayisyen',
              flag: '\ud83c\udded\ud83c\uddf9',
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
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.teal)
          : null,
      onTap: onTap,
    );
  }
}
