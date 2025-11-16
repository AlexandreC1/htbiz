import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../models/business_model.dart';
import '../../models/review_model.dart';
import '../../services/localization_service.dart';
import '../business/business_detail_screen.dart';

class CustomerPage extends StatefulWidget {
  const CustomerPage({Key? key}) : super(key: key);

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage>
    with SingleTickerProviderStateMixin {
  List<Business> _favoriteBusinesses = [];
  List<Review> _myReviews = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadFavoriteBusinesses(),
        _loadMyReviews(),
      ]);

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadFavoriteBusinesses() async {
    // For now, we'll show top-rated businesses
    // You can add a favorites table in the future
    try {
      final response = await supabase
          .from('businesses')
          .select()
          .gte('rating', 4.0)
          .order('rating', ascending: false)
          .limit(10);

      final businesses = (response as List)
          .map((json) => Business.fromJson(json))
          .toList();

      setState(() {
        _favoriteBusinesses = businesses;
      });
    } catch (e) {
      print('Error loading favorites: $e');
    }
  }

  Future<void> _loadMyReviews() async {
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      setState(() => _myReviews = []);
      return;
    }

    try {
      final response = await supabase
          .from('reviews')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final reviews = (response as List)
          .map((json) => Review.fromJson(json))
          .toList();

      setState(() {
        _myReviews = reviews;
      });
    } catch (e) {
      print('Error loading reviews: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final isLoggedIn = supabase.auth.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('favorites')),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: [
            Tab(
              icon: const Icon(Icons.favorite),
              text: localization.t('favorites'),
            ),
            Tab(
              icon: const Icon(Icons.rate_review),
              text: localization.t('my_reviews'),
            ),
          ],
        ),
      ),
      body: !isLoggedIn
          ? _buildLoginPrompt(localization)
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFavoritesTab(localization),
                    _buildReviewsTab(localization),
                  ],
                ),
    );
  }

  Widget _buildLoginPrompt(LocalizationService localization) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_border,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              localization.t('sign_in_for_favorites'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              localization.t('sign_in_for_favorites_desc'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesTab(LocalizationService localization) {
    if (_favoriteBusinesses.isEmpty) {
      return _buildEmptyState(
        icon: Icons.favorite_border,
        title: localization.t('no_favorites_yet'),
        subtitle: localization.t('explore_and_favorite'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _favoriteBusinesses.length,
        itemBuilder: (context, index) {
          final business = _favoriteBusinesses[index];
          return _buildBusinessCard(business, index);
        },
      ),
    );
  }

  Widget _buildReviewsTab(LocalizationService localization) {
    if (_myReviews.isEmpty) {
      return _buildEmptyState(
        icon: Icons.rate_review_outlined,
        title: localization.t('no_reviews_yet'),
        subtitle: localization.t('be_first_to_review'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myReviews.length,
        itemBuilder: (context, index) {
          final review = _myReviews[index];
          return _buildReviewCard(review, index);
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessCard(Business business, int index) {
    final localization = Provider.of<LocalizationService>(context);
    final delay = index * 100;

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 400 + delay),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BusinessDetailScreen(businessId: business.id),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Business Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: business.imageUrl != null
                      ? Image.network(
                          business.imageUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey.shade200,
                            child: Icon(
                              Icons.business,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        )
                      : Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.business,
                            color: Colors.grey.shade400,
                          ),
                        ),
                ),
                const SizedBox(width: 16),

                // Business Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        localization.t(business.category),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 16,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            business.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${business.totalReviews})',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Favorite Icon
                Icon(
                  Icons.favorite,
                  color: Colors.red.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewCard(Review review, int index) {
    final delay = index * 100;

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 400 + delay),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ...List.generate(
                    5,
                    (index) => Icon(
                      index < review.rating
                          ? Icons.star
                          : Icons.star_border,
                      size: 20,
                      color: Colors.amber.shade700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(review.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (review.comment != null && review.comment!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  review.comment!,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
              if (review.imageUrl != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    review.imageUrl!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final localization = Provider.of<LocalizationService>(context, listen: false);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return localization.t('today');
    } else if (difference.inDays == 1) {
      return localization.t('yesterday');
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ${localization.t('days_ago')}';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} ${localization.t('weeks_ago')}';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()} ${localization.t('months_ago')}';
    } else {
      return '${(difference.inDays / 365).floor()} ${localization.t('years_ago')}';
    }
  }
}
