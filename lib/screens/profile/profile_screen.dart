import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../services/localization_service.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final localization = Provider.of<LocalizationService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('profile')),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),

          // User Info
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.teal,
                  child: Text(
                    user?.email?.substring(0, 1).toUpperCase() ?? 'G',
                    style: const TextStyle(
                      fontSize: 36,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.email ?? localization.t('continue_as_guest'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (user?.isAnonymous ?? true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      localization.t('continue_as_guest'),
                      style: TextStyle(
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),

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
