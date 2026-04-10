import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/business_model.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import '../business/business_detail_screen.dart';
import '../../main.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final BusinessService _businessService = BusinessService();
  Set<Marker> _markers = {};
  Business? _selectedBusiness;
  List<Business> _businesses = [];
  Position? _userPosition;
  bool _isLoading = true;
  String? _selectedCategory;

  // Default to Haiti center
  static const _defaultCenter = LatLng(18.9712, -72.2852);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load businesses and render the map immediately — do NOT await
      // user location here. getCurrentPosition() can take many seconds and
      // was the main source of the "map takes a long time to load" delay.
      final businesses = await _businessService.getAllBusinesses();

      if (mounted) {
        setState(() {
          _businesses = businesses;
          _isLoading = false;
        });
        _buildMarkers();
      }

      // Resolve user location in the background and animate once ready.
      _resolveUserLocationInBackground();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveUserLocationInBackground() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _userPosition = pos);
      _animateToPosition();
    } catch (_) {
      // Map is already usable without location — swallow.
    }
  }

  void _buildMarkers() {
    final markers = <Marker>{};
    final filtered = _selectedCategory == null
        ? _businesses
        : _businesses.where(
            (b) => b.category.toLowerCase() == _selectedCategory!.toLowerCase());

    for (final business in filtered) {
      if (business.latitude == null || business.longitude == null) continue;

      markers.add(
        Marker(
          markerId: MarkerId(business.id),
          position: LatLng(business.latitude!, business.longitude!),
          infoWindow: InfoWindow(
            title: business.name,
            snippet:
                '${business.category} · ${business.rating.toStringAsFixed(1)}',
          ),
          icon: business.verificationStatus == 'verified'
              ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
              : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          onTap: () {
            setState(() => _selectedBusiness = business);
          },
        ),
      );
    }

    setState(() => _markers = markers);
  }

  Future<void> _animateToPosition() async {
    if (!_controller.isCompleted) return;
    final controller = await _controller.future;
    if (_userPosition != null) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_userPosition!.latitude, _userPosition!.longitude),
          13,
        ),
      );
    }
  }

  LatLng get _initialPosition {
    if (_userPosition != null) {
      return LatLng(_userPosition!.latitude, _userPosition!.longitude);
    }
    final withLocation =
        _businesses.where((b) => b.latitude != null && b.longitude != null);
    if (withLocation.isNotEmpty) {
      return LatLng(withLocation.first.latitude!, withLocation.first.longitude!);
    }
    return _defaultCenter;
  }

  void _goToBusinessDetail(Business business) {
    Navigator.push(
      context,
      FadeSlideRoute(
        page: BusinessDetailScreen(businessId: business.id),
      ),
    );
  }

  Future<void> _centerOnUser() async {
    if (_userPosition == null) return;
    final controller = await _controller.future;
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(_userPosition!.latitude, _userPosition!.longitude),
        14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final businessesOnMap = _businesses
        .where((b) => b.latitude != null && b.longitude != null)
        .length;

    final categories = [
      {'key': null, 'label': localization.t('all'), 'icon': Icons.apps_rounded},
      {'key': 'restaurant', 'label': localization.t('restaurant'), 'icon': Icons.restaurant_rounded},
      {'key': 'hotel', 'label': localization.t('hotel'), 'icon': Icons.hotel_rounded},
      {'key': 'shop', 'label': localization.t('shop'), 'icon': Icons.shopping_bag_rounded},
      {'key': 'service', 'label': localization.t('service'), 'icon': Icons.build_rounded},
      {'key': 'entertainment', 'label': localization.t('entertainment'), 'icon': Icons.celebration_rounded},
      {'key': 'healthcare', 'label': localization.t('healthcare'), 'icon': Icons.local_hospital_rounded},
      {'key': 'education', 'label': localization.t('education'), 'icon': Icons.school_rounded},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('map_view')),
        automaticallyImplyLeading: false,
        actions: [
          if (_userPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              tooltip: localization.t('my_location'),
              onPressed: _centerOnUser,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Category filter chips
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: categories.map((cat) {
                      final key = cat['key'] as String?;
                      final isSelected = _selectedCategory == key;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: Icon(
                            cat['icon'] as IconData,
                            size: 16,
                            color: isSelected ? AppColors.primary : Colors.grey[600],
                          ),
                          label: Text(
                            cat['label'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.w500,
                              color:
                                  isSelected ? AppColors.primary : Colors.grey[700],
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedCategory = key);
                            _buildMarkers();
                          },
                          selectedColor: AppColors.primaryLight,
                          backgroundColor: Colors.white,
                          checkmarkColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected ? AppColors.primary : Colors.grey.shade300,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 4),

                // Map
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _initialPosition,
                          zoom: 12,
                        ),
                        markers: _markers,
                        myLocationEnabled: _userPosition != null,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: true,
                        mapToolbarEnabled: false,
                        onMapCreated: (controller) {
                          _controller.complete(controller);
                        },
                        onTap: (_) {
                          setState(() => _selectedBusiness = null);
                        },
                      ),

                      // Business count badge
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.place, size: 16, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                '$businessesOnMap ${localization.t('on_map')}',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Selected business card
                      if (_selectedBusiness != null)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: _BusinessMapCard(
                            business: _selectedBusiness!,
                            onTap: () => _goToBusinessDetail(_selectedBusiness!),
                            onClose: () =>
                                setState(() => _selectedBusiness = null),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _BusinessMapCard extends StatelessWidget {
  final Business business;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _BusinessMapCard({
    required this.business,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: business.imageUrl != null
                    ? Image.network(
                        business.imageUrl!,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 70,
                          height: 70,
                          color: Colors.grey[300],
                          child: const Icon(Icons.store, size: 28),
                        ),
                      )
                    : Container(
                        width: 70,
                        height: 70,
                        color: Colors.grey[200],
                        child:
                            Icon(Icons.store, size: 28, color: Colors.grey[400]),
                      ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            business.name,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (business.verificationStatus == 'verified') ...[
                          const SizedBox(width: 4),
                          Icon(Icons.verified, size: 16, color: Colors.blue[600]),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      business.category,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.star, size: 14, color: Colors.amber[700]),
                        const SizedBox(width: 2),
                        Text(
                          business.rating.toStringAsFixed(1),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          ' (${business.totalReviews} ${localization.t('reviews').toLowerCase()})',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Close button
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
