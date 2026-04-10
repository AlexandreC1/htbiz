import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../main.dart';
import '../../widgets/app_toast.dart';
import '../../models/business_model.dart';
import '../../models/business_image_model.dart';
import '../../models/review_model.dart';
import '../../services/business_service.dart';
import '../../services/localization_service.dart';
import 'edit_business_screen.dart';

class BusinessDetailScreen extends StatefulWidget {
  final String businessId;

  const BusinessDetailScreen({
    super.key,
    required this.businessId,
  });

  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen> {
  final BusinessService _businessService = BusinessService();
  Business? _business;
  List<Review> _reviews = [];
  List<BusinessImage> _galleryImages = [];
  bool _isLoading = true;
  bool _isSubmittingReview = false;
  bool _isAddingPhoto = false;
  bool _isFavorite = false;
  bool _isTogglingFavorite = false;
  bool _hasCheckedIn = false;

  @override
  void initState() {
    super.initState();
    _loadBusinessDetails();
  }

  Future<void> _loadBusinessDetails() async {
    setState(() => _isLoading = true);
    try {
      final business =
          await _businessService.getBusinessById(widget.businessId);
      final reviews =
          await _businessService.getBusinessReviews(widget.businessId);
      final galleryImages =
          await _businessService.getBusinessImages(widget.businessId);

      final user = supabase.auth.currentUser;
      bool isFav = false;
      bool checkedIn = false;
      if (user != null && !user.isAnonymous) {
        final favIds = await _businessService.getFavoriteIds(user.id);
        isFav = favIds.contains(widget.businessId);
        checkedIn = await _businessService.hasCheckedIn(user.id, widget.businessId);
      }

      // Populate like counts and user's like status
      await _businessService.populateReviewLikes(
        reviews,
        (user != null && !user.isAnonymous) ? user.id : null,
      );

      setState(() {
        _business = business;
        _reviews = reviews;
        _galleryImages = galleryImages;
        _isFavorite = isFav;
        _hasCheckedIn = checkedIn;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final localization =
            Provider.of<LocalizationService>(context, listen: false);
        AppToast.error(
            context, '${localization.t('error_loading_business')}: $e');
      }
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    // Clean the phone number - remove spaces and special characters except +
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri url = Uri(scheme: 'tel', path: cleanNumber);

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        throw 'Could not launch dialer';
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Could not launch phone dialer: $e');
      }
    }
  }

  static const String _mapsApiKey = 'AIzaSyCK87tNBQvIf_u3suPF2U5Tdh7eXLsvORA';

  Future<LatLng?> _geocodeAddress(String address) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': address,
        'key': _mapsApiKey,
      });
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['status'] == 'OK') {
        final location =
            json['results'][0]['geometry']['location'] as Map<String, dynamic>;
        return LatLng(
          (location['lat'] as num).toDouble(),
          (location['lng'] as num).toDouble(),
        );
      }
    } catch (_) {}
    return null;
  }

  void _showInAppMap() async {
    final business = _business;
    if (business == null) return;

    LatLng? position;

    if (business.latitude != null && business.longitude != null) {
      position = LatLng(business.latitude!, business.longitude!);
    } else {
      // Geocode the address to get coordinates
      if (mounted) {
        AppToast.show(context, 'Loading map...',
            duration: const Duration(seconds: 2));
      }
      position = await _geocodeAddress(business.address);
    }

    if (!mounted) return;

    if (position == null) {
      // Geocoding failed — default to Haiti center
      position = const LatLng(18.9712, -72.2852);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BusinessMapScreen(
          businessName: business.name,
          address: business.address,
          position: position!,
          hasExactLocation:
              business.latitude != null && business.longitude != null,
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(String number) async {
    final clean = number.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri url = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      AppToast.error(context, 'Could not open WhatsApp');
    }
  }

  Future<void> _openWebsite(String website) async {
    final url = website.startsWith('http') ? website : 'https://$website';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      AppToast.error(context, 'Could not open website');
    }
  }

  Future<void> _toggleFavorite() async {
    final user = supabase.auth.currentUser;
    if (user == null || user.isAnonymous) {
      AppToast.warning(context, 'Sign in to save favorites');
      return;
    }
    setState(() => _isTogglingFavorite = true);
    try {
      if (_isFavorite) {
        await _businessService.removeFavorite(widget.businessId);
      } else {
        await _businessService.addFavorite(widget.businessId);
      }
      setState(() => _isFavorite = !_isFavorite);
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isTogglingFavorite = false);
    }
  }

  void _shareBusiness() {
    if (_business == null) return;
    final text = '${_business!.name}\n'
        '${_business!.category} · ${_business!.address}'
        '${_business!.phone != null ? '\n📞 ${_business!.phone}' : ''}'
        '${_business!.whatsapp != null ? '\n💬 WhatsApp: ${_business!.whatsapp}' : ''}';
    Share.share(text, subject: _business!.name);
  }

  void _showOwnerReplyDialog(Review review) {
    final replyController = TextEditingController(text: review.ownerReply ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(review.ownerReply != null ? 'Edit Reply' : 'Reply to Review'),
        content: TextField(
          controller: replyController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Write your reply...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (review.ownerReply != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _businessService.deleteReviewReply(review.id);
                await _loadBusinessDetails();
              },
              child: const Text('Delete Reply', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reply = replyController.text.trim();
              if (reply.isEmpty) return;
              Navigator.pop(context);
              await _businessService.replyToReview(review.id, reply);
              await _loadBusinessDetails();
            },
            child: const Text('Post Reply'),
          ),
        ],
      ),
    );
  }

  void _showEditBusinessDialog() {
    // Navigate to the actual edit screen
    Navigator.push(
      context,
      FadeSlideRoute(
        page: EditBusinessScreen(business: _business!),
      ),
    ).then((updated) {
      if (updated == true) {
        _loadBusinessDetails(); // Refresh the business details
      }
    });
  }

  Future<void> _checkIn() async {
    final user = supabase.auth.currentUser;
    final localization =
        Provider.of<LocalizationService>(context, listen: false);

    if (user == null || user.isAnonymous) {
      AppToast.warning(context, localization.t('sign_in_to_check_in'));
      return;
    }

    if (_hasCheckedIn) {
      AppToast.show(context, localization.t('already_checked_in'));
      return;
    }

    try {
      await _businessService.checkInToBusiness(widget.businessId);
      setState(() => _hasCheckedIn = true);
      if (mounted) {
        AppToast.success(context, localization.t('check_in_success'));
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, '${localization.t('error')}: $e');
      }
    }
  }

  void _showAddReviewDialog() {
    final user = supabase.auth.currentUser;
    final localization =
        Provider.of<LocalizationService>(context, listen: false);

    if (user == null || user.isAnonymous) {
      AppToast.warning(context, localization.t('please_sign_in_to_review'));
      return;
    }

    int selectedRating = 5;
    final commentController = TextEditingController();
    final List<File> selectedReviewImages = [];
    const int maxReviewImages = 5;
    bool isUploadingImage = false;
    bool isAnonymous = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(localization.t('add_review')),
          contentPadding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rating Section
                  Text(
                    localization.t('rating'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            selectedRating = index + 1;
                          });
                        },
                        icon: Icon(
                          index < selectedRating
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                          size: 28,
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 8),

                  // Comment Section
                  TextField(
                    controller: commentController,
                    decoration: InputDecoration(
                      labelText: localization.t('comment_optional'),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(8),
                      isDense: true,
                    ),
                    maxLines: 2,
                    maxLength: 300,
                  ),

                  const SizedBox(height: 8),

                  // Photo Section
                  Text(
                    'Add Photos (Optional) — ${selectedReviewImages.length}/$maxReviewImages',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Multi-photo picker row
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedReviewImages.length +
                          (selectedReviewImages.length < maxReviewImages ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        // Trailing add-button tile
                        if (index == selectedReviewImages.length) {
                          return InkWell(
                            onTap: () => _showReviewImagePicker(
                              setDialogState,
                              (File? image) {
                                if (image == null) return;
                                setDialogState(() {
                                  selectedReviewImages.add(image);
                                });
                              },
                            ),
                            child: Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                border: Border.all(
                                    color: Colors.grey[300]!, width: 1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      size: 28, color: Colors.grey[500]),
                                  const SizedBox(height: 2),
                                  Text('Add',
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                          );
                        }
                        final file = selectedReviewImages[index];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                file,
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    selectedReviewImages.removeAt(index);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      color: Colors.white, size: 12),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Anonymous toggle
                  Row(
                    children: [
                      Switch(
                        value: isAnonymous,
                        onChanged: (value) {
                          setDialogState(() {
                            isAnonymous = value;
                          });
                        },
                        activeColor: Colors.teal,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          localization.t('post_anonymously'),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 16.0),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localization.t('cancel')),
            ),
            ElevatedButton(
              onPressed: (_isSubmittingReview || isUploadingImage)
                  ? null
                  : () async {
                      final commentText = commentController.text.trim();
                      final rating = selectedRating;
                      final reviewImages = List<File>.from(selectedReviewImages);
                      final anonymous = isAnonymous;

                      setDialogState(() => isUploadingImage = true);
                      setState(() => _isSubmittingReview = true);
                      Navigator.pop(context);

                      try {
                        // Upload all selected review images in parallel
                        final List<String> reviewImageUrls = reviewImages.isEmpty
                            ? const []
                            : await _businessService
                                .uploadReviewImages(reviewImages);

                        // Get user display name from profile
                        String displayName = localization.t('anonymous');
                        if (!anonymous) {
                          final profile =
                              await _businessService.getProfile(user.id);
                          displayName = profile?.fullName ??
                              user.email ??
                              localization.t('anonymous');
                        }

                        final review = Review(
                          id: '',
                          businessId: widget.businessId,
                          userId: user.id,
                          rating: rating,
                          comment: commentText.isNotEmpty
                              ? commentText
                              : null,
                          createdAt: DateTime.now(),
                          userName: displayName,
                          userEmail: user.email,
                          imageUrls: reviewImageUrls,
                          isVerifiedVisit: _hasCheckedIn,
                        );

                        await _businessService.addReview(review);

                        // Stats are updated by DB trigger automatically
                        await _loadBusinessDetails();

                        final rootCtx = navigatorKey.currentContext;
                        if (mounted && rootCtx != null) {
                          AppToast.success(rootCtx,
                              localization.t('review_added_success'));
                        }
                      } catch (e) {
                        final rootCtx = navigatorKey.currentContext;
                        if (mounted && rootCtx != null) {
                          AppToast.error(
                              rootCtx, '${localization.t('error')}: $e');
                        }
                      } finally {
                        setState(() => _isSubmittingReview = false);
                      }
                    },
              child: (_isSubmittingReview || isUploadingImage)
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(localization.t('submit')),
            ),
          ],
        ),
      ),
    );
  }

  void _showReviewImagePicker(
      StateSetter setDialogState, Function(File?) onImageSelected) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final XFile? image = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1920,
                    maxHeight: 1080,
                    imageQuality: 85,
                  );
                  if (image != null) {
                    onImageSelected(File(image.path));
                  }
                } catch (e) {
                  final rootCtx = navigatorKey.currentContext;
                  if (mounted && rootCtx != null) {
                    AppToast.error(rootCtx, 'Error picking image: $e');
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final XFile? image = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1920,
                    maxHeight: 1080,
                    imageQuality: 85,
                  );
                  if (image != null) {
                    onImageSelected(File(image.path));
                  }
                } catch (e) {
                  final rootCtx = navigatorKey.currentContext;
                  if (mounted && rootCtx != null) {
                    AppToast.error(rootCtx, 'Error taking photo: $e');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation() {
    final localization =
        Provider.of<LocalizationService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.t('delete_business')),
        content: Text(localization.t('delete_confirmation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localization.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final navigator = Navigator.of(context);
              try {
                await _businessService.deleteBusiness(widget.businessId);
                if (mounted) {
                  navigator.pop(true);
                  final rootCtx = navigatorKey.currentContext;
                  if (rootCtx != null) {
                    AppToast.success(rootCtx,
                        localization.t('business_deleted_success'));
                  }
                }
              } catch (e) {
                final rootCtx = navigatorKey.currentContext;
                if (mounted && rootCtx != null) {
                  AppToast.error(rootCtx, '${localization.t('error')}: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(localization.t('delete')),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGallery(bool isOwner) {
    // Collect all photos: main image + gallery images
    final List<String> allPhotos = [];
    if (_business?.imageUrl != null) allPhotos.add(_business!.imageUrl!);
    allPhotos.addAll(_galleryImages.map((img) => img.imageUrl));

    const maxPhotos = 6;
    final canAddMore = isOwner && allPhotos.length < maxPhotos;

    if (allPhotos.isEmpty && !isOwner) {
      return Container(
        height: 220,
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.business, size: 80, color: Colors.grey),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: allPhotos.length + (canAddMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Add photo button at the end
          if (index == allPhotos.length) {
            return _isAddingPhoto
                ? Container(
                    width: 160,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(child: CircularProgressIndicator()),
                  )
                : GestureDetector(
                    onTap: _addGalleryPhoto,
                    child: Container(
                      width: 160,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.teal, style: BorderStyle.solid),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate,
                              size: 40, color: Colors.teal),
                          const SizedBox(height: 8),
                          Text(
                            'Add Photo\n(${allPhotos.length}/$maxPhotos)',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.teal, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
          }

          final imageUrl = allPhotos[index];
          // For gallery images (index > 0 if main image exists), find the BusinessImage
          final isMainImage = index == 0 && _business?.imageUrl != null;
          final galleryIndex =
              isMainImage ? -1 : index - (_business?.imageUrl != null ? 1 : 0);
          final galleryImage =
              galleryIndex >= 0 && galleryIndex < _galleryImages.length
                  ? _galleryImages[galleryIndex]
                  : null;

          return GestureDetector(
            onTap: () => _showFullImageDialog(context, imageUrl),
            onLongPress: (isOwner && !isMainImage && galleryImage != null)
                ? () => _confirmDeletePhoto(galleryImage)
                : null,
            child: Stack(
              children: [
                Container(
                  width: 220,
                  margin: const EdgeInsets.all(4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[300],
                        child:
                            const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                if (isOwner && !isMainImage && galleryImage != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _confirmDeletePhoto(galleryImage),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addGalleryPhoto() async {
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final image = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1920,
                  maxHeight: 1080,
                  imageQuality: 85,
                );
                if (image != null) await _uploadGalleryPhoto(File(image.path));
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                final image = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1920,
                  maxHeight: 1080,
                  imageQuality: 85,
                );
                if (image != null) await _uploadGalleryPhoto(File(image.path));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadGalleryPhoto(File imageFile) async {
    setState(() => _isAddingPhoto = true);
    try {
      final newImage = await _businessService.addBusinessImage(
          widget.businessId, imageFile);
      setState(() => _galleryImages.add(newImage));
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error uploading photo: $e');
      }
    } finally {
      if (mounted) setState(() => _isAddingPhoto = false);
    }
  }

  Future<void> _confirmDeletePhoto(BusinessImage image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Remove this photo from your business?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _businessService.deleteBusinessImage(image.id, image.imageUrl);
        setState(() => _galleryImages.removeWhere((img) => img.id == image.id));
      } catch (e) {
        if (mounted) {
          AppToast.error(context, 'Error deleting photo: $e');
        }
      }
    }
  }

  void _showFullImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.white, size: 60),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final isOwner = user != null && _business?.ownerId == user.id;
    final localization = Provider.of<LocalizationService>(context);

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _business == null
              ? const Center(child: Text('Business not found'))
              : CustomScrollView(
                  slivers: [
                    // App Bar
                    SliverAppBar(
                      pinned: true,
                      actions: [
                        // Share button
                        IconButton(
                          icon: const Icon(Icons.share),
                          onPressed: _shareBusiness,
                        ),
                        // Favorite button
                        if (!isOwner)
                          _isTogglingFavorite
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                                    color: _isFavorite ? Colors.red : null,
                                  ),
                                  onPressed: _toggleFavorite,
                                ),
                        if (isOwner)
                          PopupMenuButton(
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    const Icon(Icons.edit, color: Colors.blue),
                                    const SizedBox(width: 8),
                                    Text(localization.t('edit_business')),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(Icons.delete, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Text(localization.t('delete_business')),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showEditBusinessDialog();
                              } else if (value == 'delete') {
                                _showDeleteConfirmation();
                              }
                            },
                          ),
                      ],
                    ),

                    // Photo gallery strip
                    SliverToBoxAdapter(
                      child: _buildPhotoGallery(isOwner),
                    ),

                    // Business Details
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name and Category
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _business!.name,
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (_business!.verificationStatus == 'verified') ...[
                                        const SizedBox(width: 8),
                                        Tooltip(
                                          message: localization.t('verified_business'),
                                          child: Icon(
                                            Icons.verified,
                                            color: Colors.blue[600],
                                            size: 24,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.teal[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _business!.category,
                                    style: TextStyle(
                                      color: Colors.teal[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Rating
                            Row(
                              children: [
                                const Icon(Icons.star,
                                    color: Colors.amber, size: 28),
                                const SizedBox(width: 8),
                                Text(
                                  _business!.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  ' (${_business!.totalReviews} ${localization.t('reviews').toLowerCase()})',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Description
                            Text(
                              localization.t('about'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _business!.description,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[700],
                                height: 1.5,
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Contact Information
                            Text(
                              localization.t('contact'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Address
                            InkWell(
                              onTap: _showInAppMap,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_on,
                                        color: Colors.teal),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _business!.address,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                    const Icon(Icons.map_outlined,
                                        size: 20, color: Colors.teal),
                                  ],
                                ),
                              ),
                            ),

                            // Phone
                            if (_business!.phone != null)
                              InkWell(
                                onTap: () => _makePhoneCall(_business!.phone!),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.phone, color: Colors.teal),
                                      const SizedBox(width: 12),
                                      Text(_business!.phone!, style: const TextStyle(fontSize: 16)),
                                      const Spacer(),
                                      const Icon(Icons.call, size: 20),
                                    ],
                                  ),
                                ),
                              ),

                            // WhatsApp
                            if (_business!.whatsapp != null)
                              InkWell(
                                onTap: () => _openWhatsApp(_business!.whatsapp!),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.chat, color: Color(0xFF25D366)),
                                      const SizedBox(width: 12),
                                      Text(_business!.whatsapp!, style: const TextStyle(fontSize: 16)),
                                      const Spacer(),
                                      const Icon(Icons.open_in_new, size: 20),
                                    ],
                                  ),
                                ),
                              ),

                            // Website
                            if (_business!.website != null)
                              InkWell(
                                onTap: () => _openWebsite(_business!.website!),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.language, color: Colors.teal),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _business!.website!,
                                          style: const TextStyle(fontSize: 16, color: Colors.blue),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(Icons.open_in_new, size: 20),
                                    ],
                                  ),
                                ),
                              ),

                            // Hours
                            if (_business!.hoursText != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.schedule, color: Colors.teal),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _business!.hoursText!,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 24),

                            // Check-in & Review Buttons
                            Row(
                              children: [
                                // Check-in button
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _checkIn,
                                    icon: Icon(
                                      _hasCheckedIn ? Icons.check_circle : Icons.place,
                                      color: _hasCheckedIn ? Colors.green : null,
                                    ),
                                    label: Text(
                                      _hasCheckedIn
                                          ? localization.t('checked_in')
                                          : localization.t('check_in'),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 48),
                                      side: BorderSide(
                                        color: _hasCheckedIn ? Colors.green : Colors.teal,
                                      ),
                                      foregroundColor: _hasCheckedIn ? Colors.green : Colors.teal,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Write Review button
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _showAddReviewDialog,
                                    icon: const Icon(Icons.rate_review),
                                    label: Text(localization.t('write_review')),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 48),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Reviews Section
                            Row(
                              children: [
                                Text(
                                  localization.t('reviews'),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '(${_reviews.length})',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Reviews List
                            if (_reviews.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.rate_review_outlined,
                                        size: 60,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        localization.t('no_reviews_yet'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        localization.t('be_first_to_review'),
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _reviews.length,
                                itemBuilder: (context, index) {
                                  final review = _reviews[index];
                                  return _ReviewCard(
                                    review: review,
                                    isOwner: isOwner,
                                    onReply: () => _showOwnerReplyDialog(review),
                                    businessService: _businessService,
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final Review review;
  final bool isOwner;
  final VoidCallback onReply;
  final BusinessService businessService;

  const _ReviewCard({
    required this.review,
    required this.isOwner,
    required this.onReply,
    required this.businessService,
  });

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  late int _likesCount;
  late bool _isLikedByMe;
  bool _isTogglingLike = false;

  @override
  void initState() {
    super.initState();
    _likesCount = widget.review.likesCount;
    _isLikedByMe = widget.review.isLikedByMe;
  }

  Future<void> _toggleLike() async {
    final user = supabase.auth.currentUser;
    final localization =
        Provider.of<LocalizationService>(context, listen: false);

    if (user == null || user.isAnonymous) {
      AppToast.warning(context, localization.t('sign_in_to_like'));
      return;
    }

    if (_isTogglingLike) return;
    setState(() => _isTogglingLike = true);

    try {
      if (_isLikedByMe) {
        await widget.businessService.unlikeReview(widget.review.id);
        setState(() {
          _isLikedByMe = false;
          _likesCount--;
        });
      } else {
        await widget.businessService.likeReview(widget.review.id);
        setState(() {
          _isLikedByMe = true;
          _likesCount++;
        });
      }
    } catch (e) {
      // Silently fail
    } finally {
      if (mounted) setState(() => _isTogglingLike = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = Provider.of<LocalizationService>(context);
    final review = widget.review;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info and rating
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Text(
                    (review.userName ?? review.userEmail ?? 'A')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              review.userName ?? review.userEmail ?? 'Anonymous',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Verified visit badge
                          if (review.isVerifiedVisit) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green[300]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified,
                                      size: 12, color: Colors.green[700]),
                                  const SizedBox(width: 2),
                                  Text(
                                    localization.t('verified_visit'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Row(
                            children: List.generate(5, (index) {
                              return Icon(
                                index < review.rating
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Colors.amber,
                                size: 16,
                              );
                            }),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(review.createdAt, localization),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Review comment
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                review.comment!,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ],

            // Review images (supports multiple)
            if (review.allImages.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: review.allImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final url = review.allImages[i];
                    return GestureDetector(
                      onTap: () => _showFullImageDialog(context, url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                          loadingBuilder: (c, child, p) {
                            if (p == null) return child;
                            return Container(
                              width: 110,
                              height: 110,
                              color: Colors.grey[200],
                              child: const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            );
                          },
                          errorBuilder: (c, e, s) => Container(
                            width: 110,
                            height: 110,
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image,
                                color: Colors.grey, size: 32),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Like button row
            Row(
              children: [
                InkWell(
                  onTap: _toggleLike,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isLikedByMe
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                          size: 18,
                          color: _isLikedByMe ? Colors.blue : Colors.grey[600],
                        ),
                        if (_likesCount > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '$_likesCount',
                            style: TextStyle(
                              fontSize: 13,
                              color: _isLikedByMe
                                  ? Colors.blue
                                  : Colors.grey[600],
                              fontWeight: _isLikedByMe
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // Owner reply button (only shown to owner)
                if (widget.isOwner)
                  TextButton.icon(
                    onPressed: widget.onReply,
                    icon: Icon(
                      review.ownerReply != null ? Icons.edit : Icons.reply,
                      size: 16,
                    ),
                    label: Text(
                      review.ownerReply != null ? 'Edit Reply' : 'Reply',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),

            // Owner reply display
            if (review.ownerReply != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                      left: BorderSide(color: Colors.teal[300]!, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, size: 14, color: Colors.teal[700]),
                        const SizedBox(width: 4),
                        Text(
                          'Owner Reply',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.teal[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      review.ownerReply!,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.white, size: 60),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date, LocalizationService localization) {
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

// ============================================================
// Full-screen in-app map for viewing business location
// ============================================================

class _BusinessMapScreen extends StatelessWidget {
  final String businessName;
  final String address;
  final LatLng position;
  final bool hasExactLocation;

  const _BusinessMapScreen({
    required this.businessName,
    required this.address,
    required this.position,
    required this.hasExactLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          businessName,
          style: const TextStyle(fontSize: 18),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: position,
              zoom: hasExactLocation ? 16 : 12,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('business'),
                position: position,
                infoWindow: InfoWindow(
                  title: businessName,
                  snippet: address,
                ),
              ),
            },
            zoomControlsEnabled: true,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapToolbarEnabled: false,
          ),
          // Address bar at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!hasExactLocation)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.orange[700]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              Provider.of<LocalizationService>(context,
                                      listen: false)
                                  .t('approximate_location'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.teal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
