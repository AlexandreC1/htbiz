import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  final TextEditingController _searchController = TextEditingController();
  Set<Marker> _markers = {};
  Marker? _searchMarker;
  Business? _selectedBusiness;
  List<Business> _businesses = [];
  Position? _userPosition;
  bool _isLoading = true;
  bool _isSearching = false;
  String? _selectedCategory;
  String? _tappedAddress;
  bool _isReverseGeocoding = false;

  static const String _mapsApiKey = 'AIzaSyCK87tNBQvIf_u3suPF2U5Tdh7eXLsvORA';

  // Default to Port-au-Prince, Haiti
  static const _defaultCenter = LatLng(18.5944, -72.3074);

  // Tracks addresses we've already tried to geocode this session so we don't
  // hammer the APIs if a lookup returns null.
  final Set<String> _geocodeAttempted = {};

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

      // Geocode any businesses missing coordinates (background) so they can
      // appear on the map. Persists results back to the DB to avoid
      // re-geocoding on every launch.
      _geocodeMissingBusinesses();

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
        : _businesses.where((b) =>
            b.category.toLowerCase() == _selectedCategory!.toLowerCase());

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
            setState(() {
              _selectedBusiness = business;
              _tappedAddress = null;
              _isReverseGeocoding = false;
            });
          },
        ),
      );
    }

    setState(() => _markers = markers);
  }

  Future<void> _geocodeMissingBusinesses() async {
    final missing = _businesses
        .where((b) =>
            (b.latitude == null || b.longitude == null) &&
            b.address.trim().isNotEmpty &&
            !_geocodeAttempted.contains(b.id))
        .toList();

    if (missing.isEmpty) return;

    for (final business in missing) {
      if (!mounted) return;
      _geocodeAttempted.add(business.id);

      // Bias the query towards Haiti so Nominatim/Google pick the right place.
      final addressLower = business.address.toLowerCase();
      final query = (addressLower.contains('haiti') ||
              addressLower.contains('haïti') ||
              addressLower.contains('ht'))
          ? business.address
          : '${business.address}, Haiti';

      var result = await _geocodeViaGoogle(query);
      result ??= await _geocodeViaNominatim(query);

      if (result == null) {
        // Respect Nominatim's 1 req/sec policy even on failures.
        await Future.delayed(const Duration(milliseconds: 1100));
        continue;
      }

      final lat = result['lat'] as double;
      final lng = result['lng'] as double;

      // Update in-memory list so markers render immediately.
      final idx = _businesses.indexWhere((b) => b.id == business.id);
      if (idx != -1 && mounted) {
        _businesses[idx] =
            _businesses[idx].copyWith(latitude: lat, longitude: lng);
        _buildMarkers();
      }

      // Persist to DB so we only geocode once per business.
      try {
        await _businessService.updateBusiness(business.id, {
          'latitude': lat,
          'longitude': lng,
        });
      } catch (_) {
        // Non-fatal — markers still render this session.
      }

      // Rate-limit Nominatim.
      await Future.delayed(const Duration(milliseconds: 1100));
    }
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
      return LatLng(
          withLocation.first.latitude!, withLocation.first.longitude!);
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

  Future<Map<String, dynamic>?> _geocodeViaGoogle(String query) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': query,
        'key': _mapsApiKey,
      });
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['status'] == 'OK' && (json['results'] as List).isNotEmpty) {
        final result = json['results'][0];
        final location = result['geometry']['location'] as Map<String, dynamic>;
        return {
          'lat': (location['lat'] as num).toDouble(),
          'lng': (location['lng'] as num).toDouble(),
          'address': result['formatted_address'] as String,
        };
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _geocodeViaNominatim(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
      });
      final client = HttpClient();
      final request = await client.getUrl(uri);
      // Nominatim requires a valid User-Agent
      request.headers.set('User-Agent', 'HTBIZ/1.0 (contact@htbiz.app)');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final list = jsonDecode(body) as List<dynamic>;
      if (list.isNotEmpty) {
        final result = list.first as Map<String, dynamic>;
        return {
          'lat': double.parse(result['lat'] as String),
          'lng': double.parse(result['lon'] as String),
          'address': result['display_name'] as String,
        };
      }
    } catch (_) {}
    return null;
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);

    // Try Google first, then fall back to OpenStreetMap Nominatim
    // (works even if the Google Geocoding API is not enabled for the key).
    var result = await _geocodeViaGoogle(query);
    result ??= await _geocodeViaNominatim(query);

    if (!mounted) return;

    if (result == null) {
      setState(() => _isSearching = false);
      final localization =
          Provider.of<LocalizationService>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localization.t('address_not_found'))),
      );
      return;
    }

    final target = LatLng(result['lat'] as double, result['lng'] as double);
    final formattedAddress = result['address'] as String;

    setState(() {
      _searchMarker = Marker(
        markerId: const MarkerId('search_result'),
        position: target,
        infoWindow: InfoWindow(title: formattedAddress),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      );
      _selectedBusiness = null;
      _tappedAddress = formattedAddress;
      _isReverseGeocoding = false;
      _isSearching = false;
    });

    if (_controller.isCompleted) {
      final controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(target, 16),
      );
    }
  }

  Future<String?> _reverseViaGoogle(LatLng position) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '${position.latitude},${position.longitude}',
        'key': _mapsApiKey,
      });
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['status'] == 'OK' && (json['results'] as List).isNotEmpty) {
        return json['results'][0]['formatted_address'] as String;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _reverseViaNominatim(LatLng position) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '${position.latitude}',
        'lon': '${position.longitude}',
        'format': 'json',
      });
      final client = HttpClient();
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'HTBIZ/1.0 (contact@htbiz.app)');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['display_name'] is String) {
        return json['display_name'] as String;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _reverseGeocode(LatLng position) async {
    setState(() {
      _tappedAddress = null;
      _isReverseGeocoding = true;
      _selectedBusiness = null;
    });
    var address = await _reverseViaGoogle(position);
    address ??= await _reverseViaNominatim(position);
    if (!mounted) return;
    setState(() {
      _tappedAddress = address;
      _isReverseGeocoding = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final businessesOnMap = _businesses
        .where((b) => b.latitude != null && b.longitude != null)
        .length;

    final categories = [
      {'key': null, 'label': localization.t('all'), 'icon': Icons.apps_rounded},
      {
        'key': 'restaurant',
        'label': localization.t('restaurant'),
        'icon': Icons.restaurant_rounded
      },
      {
        'key': 'hotel',
        'label': localization.t('hotel'),
        'icon': Icons.hotel_rounded
      },
      {
        'key': 'shop',
        'label': localization.t('shop'),
        'icon': Icons.shopping_bag_rounded
      },
      {
        'key': 'service',
        'label': localization.t('service'),
        'icon': Icons.build_rounded
      },
      {
        'key': 'entertainment',
        'label': localization.t('entertainment'),
        'icon': Icons.celebration_rounded
      },
      {
        'key': 'healthcare',
        'label': localization.t('healthcare'),
        'icon': Icons.local_hospital_rounded
      },
      {
        'key': 'education',
        'label': localization.t('education'),
        'icon': Icons.school_rounded
      },
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
                // Address search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: localization.t('search_address'),
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14, color: Colors.grey[500]),
                      prefixIcon: const Icon(Icons.search, size: 22),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchMarker = null;
                                      _tappedAddress = null;
                                    });
                                  },
                                )
                              : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5),
                      ),
                    ),
                    style: GoogleFonts.poppins(fontSize: 14),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _searchAddress,
                    onChanged: (_) => setState(() {}),
                  ),
                ),

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
                            color: isSelected
                                ? AppColors.primary
                                : Colors.grey[600],
                          ),
                          label: Text(
                            cat['label'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.grey[700],
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
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.grey.shade300,
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
                        markers: {
                          ..._markers,
                          if (_searchMarker != null) _searchMarker!,
                        },
                        myLocationEnabled: _userPosition != null,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: true,
                        mapToolbarEnabled: false,
                        onMapCreated: (controller) {
                          _controller.complete(controller);
                        },
                        onTap: (position) {
                          _reverseGeocode(position);
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
                              const Icon(Icons.place,
                                  size: 16, color: AppColors.primary),
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
                            onTap: () =>
                                _goToBusinessDetail(_selectedBusiness!),
                            onClose: () =>
                                setState(() => _selectedBusiness = null),
                          ),
                        ),

                      // Tapped location address card
                      if (_selectedBusiness == null &&
                          (_tappedAddress != null || _isReverseGeocoding))
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Card(
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.location_on,
                                        color: AppColors.primary, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _isReverseGeocoding
                                        ? Row(
                                            children: [
                                              const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                localization.t('loading'),
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey[600]),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            _tappedAddress ?? '',
                                            style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () => setState(() {
                                      _tappedAddress = null;
                                      _isReverseGeocoding = false;
                                    }),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ),
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
                        child: Icon(Icons.store,
                            size: 28, color: Colors.grey[400]),
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
                          Icon(Icons.verified,
                              size: 16, color: Colors.blue[600]),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            business.address,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
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
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
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
