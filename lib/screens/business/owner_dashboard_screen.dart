import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/business_model.dart';
import '../../models/review_model.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import 'add_business_screen.dart';
import 'analytics_dashboard_screen.dart';
import 'business_detail_screen.dart';
import 'edit_business_screen.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  final _businessService = BusinessService();
  List<Business> _businesses = [];
  Map<String, List<Review>> _reviewsByBusiness = {};
  Map<String, int> _favoriteCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final businesses = await _businessService.getOwnerBusinesses(user.id);
      final reviewsByBusiness = <String, List<Review>>{};
      final favoriteCounts = <String, int>{};

      await Future.wait(businesses.map((b) async {
        final results = await Future.wait([
          _businessService.getBusinessReviews(b.id),
          _businessService.getFavoriteCount(b.id),
        ]);
        reviewsByBusiness[b.id] = results[0] as List<Review>;
        favoriteCounts[b.id] = results[1] as int;
      }));

      if (mounted) {
        setState(() {
          _businesses = businesses;
          _reviewsByBusiness = reviewsByBusiness;
          _favoriteCounts = favoriteCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _totalReviews =>
      _reviewsByBusiness.values.fold(0, (sum, list) => sum + list.length);

  double get _overallRating {
    final rated = _businesses.where((b) => b.totalReviews > 0);
    if (rated.isEmpty) return 0;
    return rated.map((b) => b.rating).reduce((a, b) => a + b) / rated.length;
  }

  int get _totalFavorites =>
      _favoriteCounts.values.fold(0, (sum, c) => sum + c);

  Future<void> _deleteBusiness(Business business) async {
    final localization =
        Provider.of<LocalizationService>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localization.t('delete_business')),
        content: Text(localization.t('delete_confirmation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(localization.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(localization.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _businessService.deleteBusiness(business.id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localization.t('business_deleted_success')),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('your_businesses')),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: localization.t('analytics'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AnalyticsDashboardScreen()),
              ).then((_) => _loadData());
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _businesses.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.storefront_outlined,
                                    size: 80, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  localization.t('no_businesses_yet'),
                                  style: TextStyle(
                                      fontSize: 18, color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  localization.t('be_first_to_add'),
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const AddBusinessScreen()),
                                    ).then((_) => _loadData());
                                  },
                                  icon: const Icon(Icons.add),
                                  label:
                                      Text(localization.t('add_business')),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Quick stats row
                        _buildStatsRow(localization),
                        const SizedBox(height: 20),

                        // Section header
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                localization.t('your_businesses'),
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            Text(
                              '${_businesses.length}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Business cards
                        ..._businesses.map(
                            (b) => _buildBusinessTile(b, localization)),

                        // Recent activity
                        const SizedBox(height: 24),
                        Text(
                          localization.t('recent_reviews'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _buildRecentReviews(localization),

                        const SizedBox(height: 80), // space for FAB
                      ],
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddBusinessScreen()),
          ).then((_) => _loadData());
        },
        icon: const Icon(Icons.add),
        label: Text(localization.t('add_business')),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildStatsRow(LocalizationService localization) {
    return Row(
      children: [
        _buildStatCard(
          Icons.store,
          '${_businesses.length}',
          localization.t('your_businesses'),
          Colors.teal,
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          Icons.reviews,
          '$_totalReviews',
          localization.t('total_reviews'),
          Colors.blue,
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          Icons.star,
          _overallRating.toStringAsFixed(1),
          localization.t('avg_rating'),
          Colors.amber,
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          Icons.favorite,
          '$_totalFavorites',
          localization.t('total_favorites'),
          Colors.red,
        ),
      ],
    );
  }

  Widget _buildStatCard(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessTile(
      Business business, LocalizationService localization) {
    final reviews = _reviewsByBusiness[business.id] ?? [];
    final favCount = _favoriteCounts[business.id] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Tappable main area → detail screen
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      BusinessDetailScreen(businessId: business.id),
                ),
              ).then((_) => _loadData());
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: business.imageUrl != null
                        ? Image.network(
                            business.imageUrl!,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image, size: 24),
                            ),
                          )
                        : Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey[200],
                            child: Icon(Icons.store,
                                size: 28, color: Colors.grey[400]),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          business.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.star,
                                size: 14, color: Colors.amber[700]),
                            const SizedBox(width: 2),
                            Text(
                              business.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.reviews_outlined,
                                size: 14, color: Colors.blue[400]),
                            const SizedBox(width: 2),
                            Text('${reviews.length}',
                                style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                            Icon(Icons.favorite,
                                size: 14, color: Colors.red[300]),
                            const SizedBox(width: 2),
                            Text('$favCount',
                                style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          business.category,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),

          // Action buttons row
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            EditBusinessScreen(business: business),
                      ),
                    ).then((_) => _loadData());
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: Text(localization.t('edit_business'),
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
              Container(width: 1, height: 24, color: Colors.grey[300]),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _deleteBusiness(business),
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  label: Text(
                    localization.t('delete'),
                    style:
                        const TextStyle(fontSize: 13, color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentReviews(LocalizationService localization) {
    final allReviews = <MapEntry<String, Review>>[];
    for (final entry in _reviewsByBusiness.entries) {
      for (final review in entry.value) {
        allReviews.add(MapEntry(entry.key, review));
      }
    }
    allReviews.sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));
    final recent = allReviews.take(5).toList();

    if (recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            localization.t('no_reviews_yet'),
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      );
    }

    return Column(
      children: recent.map((entry) {
        final review = entry.value;
        final business =
            _businesses.firstWhere((b) => b.id == entry.key);
        final daysAgo = DateTime.now().difference(review.createdAt).inDays;
        final timeText = daysAgo == 0
            ? localization.t('today')
            : daysAgo == 1
                ? localization.t('yesterday')
                : '$daysAgo ${localization.t('days_ago')}';

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.amber,
              child: Text(
                '${review.rating}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            title: Text(
              business.name,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text(
              review.comment ?? '★' * review.rating,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Text(
              timeText,
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ),
        );
      }).toList(),
    );
  }
}
