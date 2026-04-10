import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/offline_banner.dart';
import '../../services/connectivity_service.dart';
import '../../models/business_model.dart';
import '../../models/user_profile.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import '../../widgets/htbiz_logo.dart';
import '../business/add_business_screen.dart';
import '../business/business_detail_screen.dart';
import '../main_shell.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  final MainShellState? shell;

  const HomeScreen({super.key, this.shell});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final BusinessService _businessService = BusinessService();
  List<Business> _businesses = [];
  List<Business> _filteredBusinesses = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCategory;
  UserProfile? _userProfile;
  Set<String> _favoriteIds = {};
  bool _showFavoritesOnly = false;
  bool _sortByDistance = false;
  bool _isResolvingLocation = false;
  Position? _userPosition;
  Map<String, double> _distances = {};

  late AnimationController _listAnimController;

  // Public getters for map screen
  List<Business> get businesses => _businesses;
  List<Business> get filteredBusinesses => _filteredBusinesses;
  Position? get userPosition => _userPosition;

  @override
  void initState() {
    super.initState();
    _listAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _loadBusinesses();
    _loadProfile();
    ConnectivityService.instance.addListener(_onConnectivityChanged);
  }

  void _onConnectivityChanged() {
    // When the device comes back online, refresh from network so cached
    // data is replaced with fresh server data.
    if (!mounted) return;
    if (ConnectivityService.instance.isOnline) {
      _loadBusinesses();
      _loadProfile();
    }
  }

  @override
  void dispose() {
    ConnectivityService.instance.removeListener(_onConnectivityChanged);
    _listAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user != null && !(user.isAnonymous)) {
      final results = await Future.wait([
        _businessService.getProfile(user.id),
        _businessService.getFavoriteIds(user.id),
      ]);
      if (mounted) {
        setState(() {
          _userProfile = results[0] as UserProfile?;
          _favoriteIds = results[1] as Set<String>;
        });
      }
    }
  }

  Future<void> _enableLocationSorting() async {
    if (_isResolvingLocation) return; // debounce repeat taps
    setState(() => _isResolvingLocation = true);
    final localization =
        Provider.of<LocalizationService>(context, listen: false);
    try {
      // Check that location services are enabled on the device first —
      // getCurrentPosition() can otherwise hang indefinitely on some devices.
      final servicesOn = await Geolocator.isLocationServiceEnabled();
      if (!servicesOn) {
        if (mounted) {
          AppToast.warning(context, localization.t('location_unavailable'));
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          AppToast.warning(context, localization.t('location_unavailable'));
        }
        return;
      }
      // Hard timeout so the button always returns feedback even if the
      // platform never answers (common cause of "unresponsive" button).
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      _userPosition = position;
      _calculateDistances();
      if (!mounted) return;
      setState(() => _sortByDistance = true);
      _filterBusinesses();
    } catch (_) {
      if (mounted) {
        AppToast.warning(context, localization.t('location_unavailable'));
      }
    } finally {
      if (mounted) setState(() => _isResolvingLocation = false);
    }
  }

  void _calculateDistances() {
    if (_userPosition == null) return;
    _distances = {};
    for (final b in _businesses) {
      if (b.latitude != null && b.longitude != null) {
        _distances[b.id] = BusinessService.calculateDistance(
          _userPosition!.latitude,
          _userPosition!.longitude,
          b.latitude!,
          b.longitude!,
        );
      }
    }
  }

  Future<void> _loadBusinesses() async {
    setState(() => _isLoading = true);
    // BusinessService falls back to the local cache when offline, so we only
    // need to handle a successful return here. The OfflineBanner surfaces the
    // offline state to the user instead of an error toast.
    final businesses = await _businessService.getAllBusinesses();
    if (!mounted) return;
    setState(() {
      _businesses = businesses;
      _filteredBusinesses = businesses;
      _isLoading = false;
    });
    _listAnimController.forward(from: 0);
  }

  void _filterBusinesses() {
    setState(() {
      _filteredBusinesses = _businesses.where((business) {
        final matchesSearch =
            business.name.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesCategory = _selectedCategory == null ||
            _selectedCategory == 'all' ||
            business.category.toLowerCase() == _selectedCategory!.toLowerCase();
        final matchesFavorites =
            !_showFavoritesOnly || _favoriteIds.contains(business.id);
        return matchesSearch && matchesCategory && matchesFavorites;
      }).toList();

      if (_sortByDistance && _userPosition != null) {
        _filteredBusinesses.sort((a, b) {
          final distA = _distances[a.id] ?? double.infinity;
          final distB = _distances[b.id] ?? double.infinity;
          return distA.compareTo(distB);
        });
      }
    });
    _listAnimController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final isGuest = user?.isAnonymous ?? true;
    final isBusinessOwner = !isGuest && (_userProfile?.isBusinessOwner ?? false);
    final localization = Provider.of<LocalizationService>(context);
    final isLoggedIn = user != null && !(user.isAnonymous);

    final List<Map<String, dynamic>> categories = [
      {'key': 'all', 'label': localization.t('all'), 'icon': Icons.apps_rounded},
      {'key': 'restaurant', 'label': localization.t('restaurant'), 'icon': Icons.restaurant_rounded},
      {'key': 'hotel', 'label': localization.t('hotel'), 'icon': Icons.hotel_rounded},
      {'key': 'shop', 'label': localization.t('shop'), 'icon': Icons.shopping_bag_rounded},
      {'key': 'service', 'label': localization.t('service'), 'icon': Icons.build_rounded},
      {'key': 'entertainment', 'label': localization.t('entertainment'), 'icon': Icons.celebration_rounded},
      {'key': 'healthcare', 'label': localization.t('healthcare'), 'icon': Icons.local_hospital_rounded},
      {'key': 'education', 'label': localization.t('education'), 'icon': Icons.school_rounded},
      {'key': 'other', 'label': localization.t('other'), 'icon': Icons.more_horiz_rounded},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const HTBizLogo(size: 32),
            const SizedBox(width: 10),
            Text(
              localization.t('app_name'),
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          if (supabase.auth.currentUser != null &&
              !(supabase.auth.currentUser!.isAnonymous))
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  FadeSlideRoute(
                    page: NotificationsScreen(
                      embedded: false,
                      shell: widget.shell,
                    ),
                  ),
                ).then((_) => widget.shell?.refreshNotificationCount());
              },
              icon: widget.shell != null &&
                      widget.shell!.mounted
                  ? Badge(
                      isLabelVisible: (widget.shell as MainShellState)
                              .unreadNotifications >
                          0,
                      label: Text(
                        '${(widget.shell as MainShellState).unreadNotifications}',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white),
                      ),
                      child: const Icon(Icons.notifications_outlined),
                    )
                  : const Icon(Icons.notifications_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: localization.t('search_businesses'),
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 15,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.grey[500],
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _filterBusinesses();
              },
            ),
          ),

          // Filter chips
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // Distance sort chip
                _FilterPill(
                  icon: Icons.near_me_rounded,
                  label: _isResolvingLocation
                      ? '${localization.t('sort_by_distance')}…'
                      : localization.t('sort_by_distance'),
                  selected: _sortByDistance || _isResolvingLocation,
                  activeColor: AppColors.primary,
                  loading: _isResolvingLocation,
                  onTap: () {
                    if (_isResolvingLocation) return;
                    if (!_sortByDistance) {
                      _enableLocationSorting();
                    } else {
                      setState(() => _sortByDistance = false);
                      _filterBusinesses();
                    }
                  },
                ),
                if (isLoggedIn) ...[
                  const SizedBox(width: 8),
                  _FilterPill(
                    icon: _showFavoritesOnly
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: localization.t('favorites'),
                    selected: _showFavoritesOnly,
                    activeColor: Colors.red,
                    onTap: () {
                      setState(
                          () => _showFavoritesOnly = !_showFavoritesOnly);
                      _filterBusinesses();
                    },
                  ),
                ],
                const SizedBox(width: 8),
                ...categories.map((cat) {
                  final key = cat['key'] as String;
                  final isSelected = _selectedCategory == key ||
                      (key == 'all' && _selectedCategory == null);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterPill(
                      icon: cat['icon'] as IconData,
                      label: cat['label'] as String,
                      selected: isSelected,
                      activeColor: AppColors.primary,
                      onTap: () {
                        setState(() {
                          _selectedCategory =
                              key == 'all' ? null : key;
                        });
                        _filterBusinesses();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Business list
          Expanded(
            child: _isLoading
                ? _buildShimmerList()
                : _filteredBusinesses.isEmpty
                    ? _buildEmptyState(localization)
                    : RefreshIndicator(
                        onRefresh: () async {
                          await Future.wait(
                              [_loadBusinesses(), _loadProfile()]);
                        },
                        color: AppColors.primary,
                        child: AnimatedBuilder(
                          animation: _listAnimController,
                          builder: (context, _) {
                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 100),
                              itemCount: _filteredBusinesses.length,
                              itemBuilder: (context, index) {
                                final business = _filteredBusinesses[index];
                                // Staggered fade-in per item
                                final itemDelay = (index * 0.1).clamp(0.0, 0.6);
                                final itemEnd = (itemDelay + 0.4).clamp(0.0, 1.0);
                                final itemAnimation = CurvedAnimation(
                                  parent: _listAnimController,
                                  curve: Interval(itemDelay, itemEnd,
                                      curve: Curves.easeOutCubic),
                                );

                                return FadeTransition(
                                  opacity: itemAnimation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.08),
                                      end: Offset.zero,
                                    ).animate(itemAnimation),
                                    child: _BusinessCard(
                                      business: business,
                                      distance: _sortByDistance
                                          ? _distances[business.id]
                                          : null,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          FadeSlideRoute(
                                            page: BusinessDetailScreen(
                                              businessId: business.id,
                                            ),
                                          ),
                                        ).then((_) => _loadBusinesses());
                                      },
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: isBusinessOwner
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  FadeSlideRoute(page: const AddBusinessScreen()),
                ).then((_) => _loadBusinesses());
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(localization.t('add_business')),
            )
          : null,
    );
  }

  Widget _buildEmptyState(LocalizationService localization) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.storefront_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              localization.t('no_businesses_found'),
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              localization.t('be_first_to_add'),
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _ShimmerCard(delay: index * 150),
        );
      },
    );
  }
}

// --- Shimmer loading card ---

class _ShimmerCard extends StatefulWidget {
  final int delay;
  const _ShimmerCard({required this.delay});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _shimmerController.repeat();
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image placeholder
              Container(
                height: 180,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  gradient: LinearGradient(
                    begin: Alignment(-1.0 + 2.0 * _shimmerController.value, 0),
                    end: Alignment(1.0 + 2.0 * _shimmerController.value, 0),
                    colors: [
                      Colors.grey[200]!,
                      Colors.grey[100]!,
                      Colors.grey[200]!,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBar(width: 180, height: 18),
                    const SizedBox(height: 10),
                    _shimmerBar(width: double.infinity, height: 12),
                    const SizedBox(height: 6),
                    _shimmerBar(width: 220, height: 12),
                    const SizedBox(height: 12),
                    _shimmerBar(width: 140, height: 12),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * _shimmerController.value, 0),
          end: Alignment(1.0 + 2.0 * _shimmerController.value, 0),
          colors: [
            Colors.grey[200]!,
            Colors.grey[100]!,
            Colors.grey[200]!,
          ],
        ),
      ),
    );
  }
}

// --- Filter pill chip ---

class _FilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;
  final bool loading;

  const _FilterPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? activeColor : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                    ),
                  )
                : Icon(
                    icon,
                    size: 16,
                    color: selected ? activeColor : Colors.grey[600],
                  ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? activeColor : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Business card ---

class _BusinessCard extends StatelessWidget {
  final Business business;
  final double? distance;
  final VoidCallback onTap;

  const _BusinessCard({
    required this.business,
    this.distance,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Stack(
                children: [
                  if (business.imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: business.imageUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        height: 180,
                        color: Colors.grey[100],
                        child: Center(
                          child: Icon(Icons.image_outlined,
                              size: 40, color: Colors.grey[300]),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        height: 180,
                        color: Colors.grey[100],
                        child: Center(
                          child: Icon(Icons.broken_image_outlined,
                              size: 40, color: Colors.grey[300]),
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 180,
                      color: Colors.grey[100],
                      child: Center(
                        child: Icon(Icons.storefront_outlined,
                            size: 48, color: Colors.grey[300]),
                      ),
                    ),

                  // Category badge overlay
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Text(
                        business.category,
                        style: GoogleFonts.poppins(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  // Rating overlay
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: Colors.amber),
                          const SizedBox(width: 3),
                          Text(
                            business.rating.toStringAsFixed(1),
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Distance overlay
                  if (distance != null)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.near_me_rounded,
                                size: 12, color: AppColors.primary),
                            const SizedBox(width: 3),
                            Consumer<LocalizationService>(
                              builder: (context, loc, _) => Text(
                                '${distance!.toStringAsFixed(1)} ${loc.t('distance_km')}',
                                style: GoogleFonts.poppins(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              // Info section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + verified badge
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            business.name,
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (business.verificationStatus == 'verified') ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_rounded,
                            color: Colors.blue[600],
                            size: 20,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Description
                    Text(
                      business.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Address + reviews
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 15, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            business.address,
                            style: GoogleFonts.poppins(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Consumer<LocalizationService>(
                          builder: (context, localization, child) {
                            return Text(
                              '${business.totalReviews} ${localization.t('reviews').toLowerCase()}',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
