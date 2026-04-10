import 'dart:math';
import '../models/business_model.dart';
import '../models/business_image_model.dart';
import '../models/notification_model.dart';
import '../models/review_model.dart';
import '../models/user_profile.dart';
import '../main.dart';
import 'cache_service.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class BusinessService {
  final _cache = CacheService.instance;

  // Get all businesses (cache-first fallback when offline)
  Future<List<Business>> getAllBusinesses() async {
    try {
      final response = await supabase
          .from('businesses')
          .select()
          .order('created_at', ascending: false);

      final list = (response as List).cast<Map<String, dynamic>>();
      await _cache.save('all_businesses', list);
      return list.map((json) => Business.fromJson(json)).toList();
    } catch (_) {
      // Network/offline failure — fall back to cached data if available.
      final cached = await _cache.readList('all_businesses');
      if (cached != null) {
        return cached.map((j) => Business.fromJson(j)).toList();
      }
      return [];
    }
  }

  // Get businesses by category
  Future<List<Business>> getBusinessesByCategory(String category) async {
    try {
      final response = await supabase
          .from('businesses')
          .select()
          .eq('category', category)
          .order('created_at', ascending: false);

      return (response as List).map((json) => Business.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load businesses: $e');
    }
  }

  // Search businesses by name
  Future<List<Business>> searchBusinesses(String query) async {
    try {
      final response = await supabase
          .from('businesses')
          .select()
          .ilike('name', '%$query%')
          .order('created_at', ascending: false);

      return (response as List).map((json) => Business.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to search businesses: $e');
    }
  }

  // Get single business by ID (cache-first fallback when offline)
  Future<Business?> getBusinessById(String id) async {
    try {
      final response =
          await supabase.from('businesses').select().eq('id', id).single();
      await _cache.save('business_$id', response);
      return Business.fromJson(response);
    } catch (_) {
      final cached = await _cache.readMap('business_$id');
      if (cached != null) return Business.fromJson(cached);
      // Try to find it in the cached business list as a last resort
      final list = await _cache.readList('all_businesses');
      if (list != null) {
        final match = list.where((b) => b['id'] == id).firstOrNull;
        if (match != null) return Business.fromJson(match);
      }
      return null;
    }
  }

  // Create new business
  Future<Business> createBusiness(Business business) async {
    try {
      final response = await supabase
          .from('businesses')
          .insert(business.toJson())
          .select()
          .single();

      return Business.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create business: $e');
    }
  }

  // Update business
  Future<Business> updateBusiness(
      String id, Map<String, dynamic> updates) async {
    try {
      final response = await supabase
          .from('businesses')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

      return Business.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update business: $e');
    }
  }

  // Delete business (with proper cleanup)
  Future<void> deleteBusiness(String id) async {
    try {
      // First, delete all reviews associated with this business
      await supabase.from('reviews').delete().eq('business_id', id);

      // Then delete the business itself
      await supabase.from('businesses').delete().eq('id', id);
    } catch (e) {
      throw Exception('Failed to delete business: $e');
    }
  }

  // Get reviews for a business (cache-first fallback when offline)
  Future<List<Review>> getBusinessReviews(String businessId) async {
    try {
      final response = await supabase
          .from('reviews')
          .select()
          .eq('business_id', businessId)
          .order('created_at', ascending: false);

      final list = (response as List).cast<Map<String, dynamic>>();
      await _cache.save('reviews_$businessId', list);
      return list.map((json) => Review.fromJson(json)).toList();
    } catch (_) {
      final cached = await _cache.readList('reviews_$businessId');
      if (cached != null) {
        return cached.map((j) => Review.fromJson(j)).toList();
      }
      return [];
    }
  }

  // Add review
  Future<Review> addReview(Review review) async {
    try {
      final response = await supabase
          .from('reviews')
          .insert(review.toJson())
          .select()
          .single();

      return Review.fromJson(response);
    } catch (e) {
      throw Exception('Failed to add review: $e');
    }
  }

  // Upload business image to Supabase Storage
  Future<String> uploadBusinessImage(File imageFile) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = path.extension(imageFile.path);
      final fileName = 'businesses/$userId/$timestamp$fileExtension';

      // Upload to Supabase Storage
      await supabase.storage.from('htbiz_images').upload(fileName, imageFile);

      // Get public URL
      final imageUrl =
          supabase.storage.from('htbiz_images').getPublicUrl(fileName);

      return imageUrl;
    } catch (e) {
      throw Exception('Failed to upload business image: $e');
    }
  }

  // Upload multiple review images in parallel. Returns public URLs in the same order.
  Future<List<String>> uploadReviewImages(List<File> files) async {
    if (files.isEmpty) return const [];
    final results = await Future.wait(files.map(uploadReviewImage));
    return results;
  }

  // Upload review image to Supabase Storage
  Future<String> uploadReviewImage(File imageFile) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = path.extension(imageFile.path);
      final fileName = 'reviews/$userId/$timestamp$fileExtension';

      await supabase.storage.from('htbiz_images').upload(fileName, imageFile);
      return supabase.storage.from('htbiz_images').getPublicUrl(fileName);
    } catch (e) {
      throw Exception('Failed to upload review image: $e');
    }
  }

  // --- Profile methods ---

  Future<UserProfile?> getProfile(String userId) async {
    try {
      final response = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (response == null) return null;
      await _cache.save('profile_$userId', response);
      return UserProfile.fromJson(response);
    } catch (_) {
      final cached = await _cache.readMap('profile_$userId');
      if (cached != null) return UserProfile.fromJson(cached);
      return null;
    }
  }

  Future<void> updateProfile({
    required String userId,
    required String email,
    String? fullName,
    String? avatarUrl,
    String? role,
  }) async {
    try {
      final data = <String, dynamic>{
        'id': userId,
        'email': email,
      };
      if (fullName != null) data['full_name'] = fullName;
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;
      if (role != null) data['role'] = role;

      await supabase.from('profiles').upsert(data);
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  Future<String> uploadAvatarImage(File imageFile) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = path.extension(imageFile.path);
      final fileName = 'avatars/$userId/$timestamp$fileExtension';

      await supabase.storage.from('htbiz_images').upload(fileName, imageFile);
      return supabase.storage.from('htbiz_images').getPublicUrl(fileName);
    } catch (e) {
      throw Exception('Failed to upload avatar: $e');
    }
  }

  // --- Business gallery methods ---

  Future<List<BusinessImage>> getBusinessImages(String businessId) async {
    try {
      final response = await supabase
          .from('business_images')
          .select()
          .eq('business_id', businessId)
          .order('created_at', ascending: true);
      final list = (response as List).cast<Map<String, dynamic>>();
      await _cache.save('images_$businessId', list);
      return list.map((j) => BusinessImage.fromJson(j)).toList();
    } catch (_) {
      final cached = await _cache.readList('images_$businessId');
      if (cached != null) {
        return cached.map((j) => BusinessImage.fromJson(j)).toList();
      }
      return [];
    }
  }

  Future<BusinessImage> addBusinessImage(
      String businessId, File imageFile) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = path.extension(imageFile.path);
      final fileName = 'businesses/$userId/$timestamp$fileExtension';

      await supabase.storage.from('htbiz_images').upload(fileName, imageFile);
      final imageUrl =
          supabase.storage.from('htbiz_images').getPublicUrl(fileName);

      final response = await supabase
          .from('business_images')
          .insert({'business_id': businessId, 'image_url': imageUrl})
          .select()
          .single();
      return BusinessImage.fromJson(response);
    } catch (e) {
      throw Exception('Failed to add business image: $e');
    }
  }

  // --- Favorites methods ---

  Future<Set<String>> getFavoriteIds(String userId) async {
    try {
      final response = await supabase
          .from('favorites')
          .select('business_id')
          .eq('user_id', userId);
      final ids =
          (response as List).map((r) => r['business_id'] as String).toList();
      await _cache.save('favorites_$userId', ids);
      return ids.toSet();
    } catch (_) {
      final cached = await _cache.readStringList('favorites_$userId');
      return cached?.toSet() ?? {};
    }
  }

  Future<void> addFavorite(String businessId) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('favorites').insert({
      'user_id': userId,
      'business_id': businessId,
    });
  }

  Future<void> removeFavorite(String businessId) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase
        .from('favorites')
        .delete()
        .eq('user_id', userId)
        .eq('business_id', businessId);
  }

  Future<List<Business>> getFavoriteBusinesses(String userId) async {
    try {
      final favResponse = await supabase
          .from('favorites')
          .select('business_id')
          .eq('user_id', userId);
      final ids = (favResponse as List).map((r) => r['business_id'] as String).toList();
      if (ids.isEmpty) return [];
      final response = await supabase
          .from('businesses')
          .select()
          .inFilter('id', ids);
      return (response as List).map((j) => Business.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  // --- Owner reply methods ---

  Future<void> replyToReview(String reviewId, String reply) async {
    await supabase.from('reviews').update({
      'owner_reply': reply,
      'owner_reply_at': DateTime.now().toIso8601String(),
    }).eq('id', reviewId);
  }

  Future<void> deleteReviewReply(String reviewId) async {
    await supabase.from('reviews').update({
      'owner_reply': null,
      'owner_reply_at': null,
    }).eq('id', reviewId);
  }

  Future<void> deleteBusinessImage(String imageId, String imageUrl) async {
    try {
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      final storageIndex = pathSegments.indexOf('htbiz_images');
      if (storageIndex != -1 && storageIndex < pathSegments.length - 1) {
        final storagePath =
            pathSegments.sublist(storageIndex + 1).join('/');
        await supabase.storage.from('htbiz_images').remove([storagePath]);
      }
      await supabase.from('business_images').delete().eq('id', imageId);
    } catch (e) {
      throw Exception('Failed to delete business image: $e');
    }
  }

  // --- Notification methods ---

  Future<List<AppNotification>> getNotifications(String userId) async {
    try {
      final response = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      final list = (response as List).cast<Map<String, dynamic>>();
      await _cache.save('notifications_$userId', list);
      return list.map((j) => AppNotification.fromJson(j)).toList();
    } catch (_) {
      final cached = await _cache.readList('notifications_$userId');
      if (cached != null) {
        return cached.map((j) => AppNotification.fromJson(j)).toList();
      }
      return [];
    }
  }

  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final response = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  Future<void> markAllNotificationsRead(String userId) async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? businessId,
    String? reviewId,
  }) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': userId,
        'type': type,
        'title': title,
        'body': body,
        'business_id': businessId,
        'review_id': reviewId,
        'is_read': false,
      });
    } catch (e) {
      // Silently fail — notifications shouldn't break core flow
    }
  }

  // --- Analytics methods ---

  Future<List<Business>> getOwnerBusinesses(String ownerId) async {
    try {
      final response = await supabase
          .from('businesses')
          .select()
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false);
      final list = (response as List).cast<Map<String, dynamic>>();
      await _cache.save('owner_businesses_$ownerId', list);
      return list.map((j) => Business.fromJson(j)).toList();
    } catch (_) {
      final cached = await _cache.readList('owner_businesses_$ownerId');
      if (cached != null) {
        return cached.map((j) => Business.fromJson(j)).toList();
      }
      return [];
    }
  }

  Future<int> getFavoriteCount(String businessId) async {
    try {
      final response = await supabase
          .from('favorites')
          .select('id')
          .eq('business_id', businessId);
      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  Future<Map<int, int>> getRatingDistribution(String businessId) async {
    try {
      final reviews = await getBusinessReviews(businessId);
      final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
      for (final r in reviews) {
        dist[r.rating] = (dist[r.rating] ?? 0) + 1;
      }
      return dist;
    } catch (e) {
      return {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    }
  }

  // --- Review likes methods ---

  Future<void> likeReview(String reviewId) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('review_likes').insert({
      'review_id': reviewId,
      'user_id': userId,
    });
  }

  Future<void> unlikeReview(String reviewId) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase
        .from('review_likes')
        .delete()
        .eq('review_id', reviewId)
        .eq('user_id', userId);
  }

  /// Populate likesCount and isLikedByMe on a list of reviews
  Future<void> populateReviewLikes(List<Review> reviews, String? currentUserId) async {
    if (reviews.isEmpty) return;
    try {
      final reviewIds = reviews.map((r) => r.id).toList();

      // Get all likes for these reviews
      final likesResponse = await supabase
          .from('review_likes')
          .select('review_id, user_id')
          .inFilter('review_id', reviewIds);

      final likes = likesResponse as List;

      // Count likes per review and check if current user liked
      final countMap = <String, int>{};
      final likedByMe = <String>{};

      for (final like in likes) {
        final rid = like['review_id'] as String;
        countMap[rid] = (countMap[rid] ?? 0) + 1;
        if (currentUserId != null && like['user_id'] == currentUserId) {
          likedByMe.add(rid);
        }
      }

      for (final review in reviews) {
        review.likesCount = countMap[review.id] ?? 0;
        review.isLikedByMe = likedByMe.contains(review.id);
      }
    } catch (e) {
      // Silently fail — likes are non-critical
    }
  }

  // --- Business verification methods ---

  /// Upload patent to PRIVATE bucket — no public URL generated
  Future<String> uploadPatentDocument(File imageFile) async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = path.extension(imageFile.path);
      final storagePath = '$userId/$timestamp$fileExtension';

      await supabase.storage.from('htbiz_patents').upload(storagePath, imageFile);
      // Store the storage path, NOT a public URL
      return storagePath;
    } catch (e) {
      throw Exception('Failed to upload patent document: $e');
    }
  }

  /// Generate a short-lived signed URL for viewing a patent (owner/admin only)
  Future<String> getPatentSignedUrl(String storagePath) async {
    try {
      final result = await supabase.storage
          .from('htbiz_patents')
          .createSignedUrl(storagePath, 300); // 5 minutes
      return result;
    } catch (e) {
      throw Exception('Failed to get patent URL: $e');
    }
  }

  Future<void> submitVerification(String businessId, String patentStoragePath) async {
    await supabase.from('businesses').update({
      'patent_doc_url': patentStoragePath,
      'verification_status': 'pending',
    }).eq('id', businessId);
  }

  // --- Check-in / Verified visit methods ---

  Future<void> checkInToBusiness(String businessId) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('check_ins').insert({
      'user_id': userId,
      'business_id': businessId,
    });
  }

  Future<bool> hasCheckedIn(String userId, String businessId) async {
    try {
      final response = await supabase
          .from('check_ins')
          .select('id')
          .eq('user_id', userId)
          .eq('business_id', businessId)
          .limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // --- Location helpers ---

  static double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371.0; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}
