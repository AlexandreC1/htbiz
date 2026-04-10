import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/user_profile.dart';
import '../services/business_service.dart';
import '../services/localization_service.dart';
import 'home/home_screen.dart';
import 'map/map_screen.dart';
import 'profile/profile_screen.dart';
import 'business/owner_dashboard_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final BusinessService _businessService = BusinessService();
  UserProfile? _userProfile;
  int _unreadNotifications = 0;
  int get unreadNotifications => _unreadNotifications;

  // Keys to preserve tab state
  final _homeKey = const PageStorageKey('home');
  final _mapKey = const PageStorageKey('map');
  final _profileKey = const PageStorageKey('profile');
  final _dashboardKey = const PageStorageKey('dashboard');

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = supabase.auth.currentUser;
    if (user != null && !user.isAnonymous) {
      final results = await Future.wait([
        _businessService.getProfile(user.id),
        _businessService.getUnreadNotificationCount(user.id),
      ]);
      if (mounted) {
        setState(() {
          _userProfile = results[0] as UserProfile?;
          _unreadNotifications = results[1] as int;
        });
      }
    }
  }

  void navigateToTab(int index) {
    final pageCount = _isBusinessOwner ? 4 : 3;
    if (index >= 0 && index < pageCount) {
      setState(() => _currentIndex = index);
    }
  }

  int get tabCount => _isBusinessOwner ? 4 : 3;

  void refreshNotificationCount() {
    _loadNotificationCount();
  }

  void refreshProfile() {
    _loadUserData();
  }

  Future<void> _loadNotificationCount() async {
    final user = supabase.auth.currentUser;
    if (user != null && !user.isAnonymous) {
      final count = await _businessService.getUnreadNotificationCount(user.id);
      if (mounted) setState(() => _unreadNotifications = count);
    }
  }

  bool get _isBusinessOwner =>
      _userProfile?.isBusinessOwner ?? false;

  List<Widget> _buildPages() {
    final pages = <Widget>[
      HomeScreen(key: _homeKey, shell: this),
      MapScreen(key: _mapKey),
    ];
    if (_isBusinessOwner) {
      pages.add(OwnerDashboardScreen(key: _dashboardKey));
    }
    pages.add(ProfileScreen(key: _profileKey, shell: this));
    return pages;
  }

  List<BottomNavigationBarItem> _buildNavItems(LocalizationService loc) {
    final items = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        icon: const Icon(Icons.home_outlined),
        activeIcon: const Icon(Icons.home_rounded),
        label: loc.t('home'),
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.map_outlined),
        activeIcon: const Icon(Icons.map_rounded),
        label: loc.t('map_view'),
      ),
    ];

    if (_isBusinessOwner) {
      items.add(BottomNavigationBarItem(
        icon: const Icon(Icons.storefront_outlined),
        activeIcon: const Icon(Icons.storefront_rounded),
        label: loc.t('dashboard'),
      ));
    }

    items.add(BottomNavigationBarItem(
      icon: const Icon(Icons.person_outlined),
      activeIcon: const Icon(Icons.person_rounded),
      label: loc.t('profile'),
    ));

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final pages = _buildPages();
    final navItems = _buildNavItems(localization);

    // Clamp index if tabs changed (e.g., role change)
    if (_currentIndex >= pages.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: Colors.grey[500],
          selectedFontSize: 12,
          unselectedFontSize: 11,
          selectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w500),
          items: navItems,
        ),
      ),
    );
  }
}
