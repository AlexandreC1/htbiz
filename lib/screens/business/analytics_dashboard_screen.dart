import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../main.dart';
import '../../models/business_model.dart';
import '../../models/review_model.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import 'business_detail_screen.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  final _businessService = BusinessService();
  List<Business> _businesses = [];
  Map<String, List<Review>> _reviewsByBusiness = {};
  Map<String, int> _favoriteCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
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
    if (_businesses.isEmpty) return 0;
    final rated = _businesses.where((b) => b.totalReviews > 0);
    if (rated.isEmpty) return 0;
    return rated.map((b) => b.rating).reduce((a, b) => a + b) / rated.length;
  }

  int get _totalFavorites =>
      _favoriteCounts.values.fold(0, (sum, c) => sum + c);

  Map<int, int> get _aggregateRatingDistribution {
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final reviews in _reviewsByBusiness.values) {
      for (final r in reviews) {
        dist[r.rating] = (dist[r.rating] ?? 0) + 1;
      }
    }
    return dist;
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('analytics')),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _businesses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.analytics_outlined,
                          size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        localization.t('no_businesses_yet'),
                        style: TextStyle(
                            fontSize: 18, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAnalytics,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Summary cards
                      _buildSummaryRow(localization),
                      const SizedBox(height: 24),

                      // Rating distribution chart
                      _buildRatingChart(localization),
                      const SizedBox(height: 24),

                      // Per-business breakdown
                      Text(
                        localization.t('your_businesses'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ..._businesses
                          .map((b) => _buildBusinessCard(b, localization)),

                      // Recent reviews across all businesses
                      const SizedBox(height: 24),
                      Text(
                        localization.t('recent_reviews'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _buildRecentReviews(localization),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryRow(LocalizationService localization) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.store,
            value: '${_businesses.length}',
            label: localization.t('your_businesses'),
            color: Colors.teal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            icon: Icons.reviews,
            value: '$_totalReviews',
            label: localization.t('total_reviews'),
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            icon: Icons.star,
            value: _overallRating.toStringAsFixed(1),
            label: localization.t('avg_rating'),
            color: Colors.amber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            icon: Icons.favorite,
            value: '$_totalFavorites',
            label: localization.t('total_favorites'),
            color: Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildRatingChart(LocalizationService localization) {
    final dist = _aggregateRatingDistribution;
    final maxCount =
        dist.values.fold(0, (a, b) => a > b ? a : b).toDouble();

    if (_totalReviews == 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localization.t('rating_distribution'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxCount > 0 ? maxCount + 1 : 5,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final star = value.toInt() + 1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('$star★',
                                style: const TextStyle(fontSize: 12)),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: List.generate(5, (i) {
                    final star = i + 1;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: (dist[star] ?? 0).toDouble(),
                          color: _starColor(star),
                          width: 28,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _starColor(int star) {
    switch (star) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.amber;
      case 4:
        return Colors.lightGreen;
      case 5:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildBusinessCard(
      Business business, LocalizationService localization) {
    final reviews = _reviewsByBusiness[business.id] ?? [];
    final favCount = _favoriteCounts[business.id] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            FadeSlideRoute(
              page: BusinessDetailScreen(businessId: business.id),
            ),
          ).then((_) => _loadAnalytics());
        },
        child: Padding(
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
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      business.category,
                      style: TextStyle(
                          color: Colors.teal[700],
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildMiniStat(
                      Icons.star, Colors.amber, business.rating.toStringAsFixed(1)),
                  const SizedBox(width: 16),
                  _buildMiniStat(Icons.reviews, Colors.blue,
                      '${reviews.length} ${localization.t('reviews').toLowerCase()}'),
                  const SizedBox(width: 16),
                  _buildMiniStat(
                      Icons.favorite, Colors.red, '$favCount'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
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
    final recent = allReviews.take(10).toList();

    if (recent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _starColor(review.rating),
              child: Text(
                '${review.rating}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              business.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              review.comment ?? '★' * review.rating,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              timeText,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
