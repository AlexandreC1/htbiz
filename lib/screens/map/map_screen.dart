import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../models/business_model.dart';
import '../../services/localization_service.dart';
import '../business/business_detail_screen.dart';
import '../../main.dart';

class MapScreen extends StatefulWidget {
  final List<Business> businesses;
  final Position? userPosition;

  const MapScreen({
    super.key,
    required this.businesses,
    this.userPosition,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  Set<Marker> _markers = {};
  Business? _selectedBusiness;

  // Default to Haiti center
  static const _defaultCenter = LatLng(18.9712, -72.2852);

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  void _buildMarkers() {
    final markers = <Marker>{};

    for (final business in widget.businesses) {
      if (business.latitude == null || business.longitude == null) continue;

      markers.add(
        Marker(
          markerId: MarkerId(business.id),
          position: LatLng(business.latitude!, business.longitude!),
          infoWindow: InfoWindow(
            title: business.name,
            snippet: '${business.category} · ★ ${business.rating.toStringAsFixed(1)}',
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

  LatLng get _initialPosition {
    if (widget.userPosition != null) {
      return LatLng(widget.userPosition!.latitude, widget.userPosition!.longitude);
    }
    // If businesses with location exist, center on the first one
    final withLocation = widget.businesses
        .where((b) => b.latitude != null && b.longitude != null);
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
    if (widget.userPosition == null) return;
    final controller = await _controller.future;
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(widget.userPosition!.latitude, widget.userPosition!.longitude),
        14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final businessesWithLocation = widget.businesses
        .where((b) => b.latitude != null && b.longitude != null)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('map_view')),
        actions: [
          if (widget.userPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              tooltip: localization.t('my_location'),
              onPressed: _centerOnUser,
            ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialPosition,
              zoom: 12,
            ),
            markers: _markers,
            myLocationEnabled: widget.userPosition != null,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              child: Text(
                '$businessesWithLocation ${localization.t('on_map')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
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
                onClose: () => setState(() => _selectedBusiness = null),
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
                        child: Icon(Icons.store, size: 28, color: Colors.grey[400]),
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
                            style: const TextStyle(
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
                          style: const TextStyle(
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
