import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/business_model.dart';
import '../../models/user_profile.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import '../auth/login_screen.dart';
import '../business/add_business_screen.dart';
import '../business/business_detail_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BusinessService _businessService = BusinessService();
  List<Business> _businesses = [];
  List<Business> _filteredBusinesses = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCategory;
  UserProfile? _userProfile;
  Set<String> _favoriteIds = {};
  bool _showFavoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
    _loadProfile();
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

  Future<void> _loadBusinesses() async {
    setState(() => _isLoading = true);
    try {
      final businesses = await _businessService.getAllBusinesses();
      setState(() {
        _businesses = businesses;
        _filteredBusinesses = businesses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final localization =
            Provider.of<LocalizationService>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${localization.t('error_loading_businesses')}: $e')),
        );
      }
    }
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final isGuest = user?.isAnonymous ?? true;
    final isBusinessOwner = !isGuest && (_userProfile?.isBusinessOwner ?? false);
    final localization = Provider.of<LocalizationService>(context);

    final isLoggedIn = user != null && !(user.isAnonymous);

    final List<Map<String, String>> categories = [
      {'key': 'all', 'label': localization.t('all')},
      {'key': 'restaurant', 'label': localization.t('restaurant')},
      {'key': 'hotel', 'label': localization.t('hotel')},
      {'key': 'shop', 'label': localization.t('shop')},
      {'key': 'service', 'label': localization.t('service')},
      {'key': 'entertainment', 'label': localization.t('entertainment')},
      {'key': 'healthcare', 'label': localization.t('healthcare')},
      {'key': 'education', 'label': localization.t('education')},
      {'key': 'other', 'label': localization.t('other')},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('app_name')),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: localization.t('search_businesses'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _filterBusinesses();
              },
            ),
          ),

          // Category filter + favorites toggle
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (isLoggedIn) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: Icon(
                        _showFavoritesOnly
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 16,
                        color: _showFavoritesOnly ? Colors.red : null,
                      ),
                      label: Text(localization.t('favorites')),
                      selected: _showFavoritesOnly,
                      selectedColor: Colors.red[50],
                      checkmarkColor: Colors.red,
                      onSelected: (selected) {
                        setState(() => _showFavoritesOnly = selected);
                        _filterBusinesses();
                      },
                    ),
                  ),
                ],
                ...categories.map((category) {
                  final categoryKey = category['key']!;
                  final isSelected = _selectedCategory == categoryKey ||
                      (categoryKey == 'all' && _selectedCategory == null);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(category['label']!),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory =
                              categoryKey == 'all' ? null : categoryKey;
                        });
                        _filterBusinesses();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Business list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredBusinesses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.business_outlined,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              localization.t('no_businesses_found'),
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              localization.t('be_first_to_add'),
                              style: TextStyle(
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await Future.wait([_loadBusinesses(), _loadProfile()]);
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredBusinesses.length,
                          itemBuilder: (context, index) {
                            final business = _filteredBusinesses[index];
                            return _BusinessCard(
                              business: business,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BusinessDetailScreen(
                                      businessId: business.id,
                                    ),
                                  ),
                                ).then((_) => _loadBusinesses());
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
                  MaterialPageRoute(
                    builder: (_) => const AddBusinessScreen(),
                  ),
                ).then((_) => _loadBusinesses());
              },
              icon: const Icon(Icons.add),
              label: Text(localization.t('add_business')),
            )
          : null,
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final Business business;
  final VoidCallback onTap;

  const _BusinessCard({
    required this.business,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Business image
            if (business.imageUrl != null)
              Image.network(
                business.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image, size: 50),
                  );
                },
              )
            else
              Container(
                height: 200,
                color: Colors.grey[300],
                child: const Center(
                  child: Icon(Icons.business, size: 50, color: Colors.grey),
                ),
              ),

            // Business info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          business.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.teal[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          business.category,
                          style: TextStyle(
                            color: Colors.teal[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    business.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          business.address,
                          style: const TextStyle(color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        business.rating.toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Consumer<LocalizationService>(
                        builder: (context, localization, child) {
                          return Text(
                            ' (${business.totalReviews} ${localization.t('reviews').toLowerCase()})',
                            style: const TextStyle(color: Colors.grey),
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
    );
  }
}
