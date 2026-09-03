import 'dart:io';
import 'dart:math';

import '../main.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../models/business_image_model.dart';
import '../models/business_model.dart';
import '../models/notification_model.dart';
import '../models/review_model.dart';
import '../models/user_profile.dart';
import '../utils/upload_validator.dart';
import 'app_exception.dart';
import 'cache_service.dart';

/// A page of results plus whether more exist.
///
/// `getAllBusinesses()` used to `SELECT *` with no limit. Supabase caps that at
/// `max_rows = 1000`, so past a thousand businesses the directory would have
/// silently stopped growing — and every launch would have pulled a thousand
/// rows over a mobile connection.
class PagedResult<T> {
  const PagedResult(
      {required this.items, required this.hasMore, this.fromCache = false});

  final List<T> items;
  final bool hasMore;

  /// True when the network failed and these came from the offline cache.
  final bool fromCache;

  bool get isEmpty => items.isEmpty;
}

class BusinessService {
  final _cache = CacheService.instance;

  /// Default rows per request. Small enough to render fast on a slow link.
  static const int pageSize = 20;

  // ===========================================================================
  // Identity
  // ===========================================================================

  /// The signed-in user's id, or a typed failure.
  ///
  /// Every write used to read `supabase.auth.currentUser!.id`. Once a refresh
  /// token expired — which happens whenever the app is left closed long enough
  /// — that bang threw a raw `TypeError` from inside the service and crashed
  /// the frame instead of sending the user back to the login screen.
  String get _requireUserId {
    final id = supabase.auth.currentUser?.id;
    if (id == null) {
      throw const AppException(
        AppErrorKind.unauthenticated,
        'Please sign in to continue.',
      );
    }
    return id;
  }

  String? get currentUserId => supabase.auth.currentUser?.id;

  bool get isSignedIn => supabase.auth.currentUser != null;

  // ===========================================================================
  // Businesses — reads
  // ===========================================================================

  /// One page of the directory, newest first.
  Future<PagedResult<Business>> getBusinessPage({
    int offset = 0,
    int limit = pageSize,
    String? category,
  }) async {
    try {
      // Ask for one extra row: if it comes back, there is another page.
      final rows = await Net.call(
        () async {
          var query =
              supabase.from('businesses').select().isFilter('deleted_at', null);
          if (category != null && category.isNotEmpty) {
            query = query.eq('category', category);
          }
          return await query
              .order('created_at', ascending: false)
              .range(offset, offset + limit);
        },
        whileDoing: 'load businesses',
      );

      final list = (rows as List).cast<Map<String, dynamic>>();
      final hasMore = list.length > limit;
      final page = hasMore ? list.sublist(0, limit) : list;

      // Only the first page is worth caching — it is what a cold, offline
      // launch renders.
      if (offset == 0 && category == null) {
        await _cache.save('all_businesses', page);
      }

      return PagedResult(
        items: page.map(Business.fromJson).toList(),
        hasMore: hasMore,
      );
    } on AppException catch (error) {
      if (offset == 0 &&
          category == null &&
          error.kind == AppErrorKind.network) {
        final cached = await _cache.readList('all_businesses');
        if (cached != null) {
          return PagedResult(
            items: cached.map(Business.fromJson).toList(),
            hasMore: false,
            fromCache: true,
          );
        }
      }
      rethrow;
    }
  }

  /// First page of the directory.
  ///
  /// Kept for call sites that do not paginate yet; prefer [getBusinessPage].
  Future<List<Business>> getAllBusinesses() async {
    final page = await getBusinessPage();
    return page.items;
  }

  Future<List<Business>> getBusinessesByCategory(String category) async {
    final page = await getBusinessPage(category: category);
    return page.items;
  }

  /// Search by name.
  ///
  /// `%` and `_` are wildcards in a LIKE pattern. The old code interpolated
  /// the raw query straight into one, so searching for a single `%` matched
  /// every business and `_` matched any character. Both are escaped here.
  Future<List<Business>> searchBusinesses(String query,
      {int limit = 50}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return getAllBusinesses();

    final pattern = '%${_escapeLikePattern(trimmed)}%';

    final rows = await Net.call(
      () => supabase
          .from('businesses')
          .select()
          .ilike('name', pattern)
          .order('created_at', ascending: false)
          .limit(limit),
      whileDoing: 'search businesses',
    );

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Business.fromJson)
        .toList();
  }

  static String _escapeLikePattern(String input) => input
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_')
      // PostgREST splits `or=(...)` filters on commas and parentheses.
      .replaceAll(',', ' ')
      .replaceAll('(', ' ')
      .replaceAll(')', ' ');

  Future<Business?> getBusinessById(String id) async {
    try {
      final response = await Net.call(
        () => supabase
            .from('businesses')
            .select()
            .eq('id', id)
            .isFilter('deleted_at', null)
            .maybeSingle(),
        whileDoing: 'load that business',
      );
      if (response == null) return null;
      await _cache.save('business_$id', response);
      return Business.fromJson(response);
    } on AppException catch (error) {
      if (error.kind != AppErrorKind.network) rethrow;

      final cached = await _cache.readMap('business_$id');
      if (cached != null) return Business.fromJson(cached);

      final list = await _cache.readList('all_businesses');
      for (final row in list ?? const <Map<String, dynamic>>[]) {
        if (row['id'] == id) return Business.fromJson(row);
      }

      rethrow;
    }
  }

  // ===========================================================================
  // Businesses — writes
  // ===========================================================================

  Future<Business> createBusiness(Business business) async {
    final userId = _requireUserId;

    final payload = business.toJson()
      ..['owner_id'] = userId
      // rating / total_reviews are maintained by a database trigger and are
      // reverted by the column guard, so do not pretend to set them.
      ..remove('rating')
      ..remove('total_reviews')
      ..remove('verification_status')
      ..remove('patent_doc_url');

    final response = await Net.call(
      () => supabase.from('businesses').insert(payload).select().single(),
      whileDoing: 'save that business',
    );

    await _cache.remove('owner_businesses_$userId');
    await _cache.remove('all_businesses');
    return Business.fromJson(response);
  }

  Future<Business> updateBusiness(
      String id, Map<String, dynamic> updates) async {
    // Stripped client-side too so the request stays honest about its intent —
    // the database guard reverts these regardless.
    final payload = Map<String, dynamic>.from(updates)
      ..remove('id')
      ..remove('owner_id')
      ..remove('rating')
      ..remove('total_reviews')
      ..remove('created_at')
      ..remove('verification_status')
      ..remove('deleted_at');

    if (payload.isEmpty) {
      final existing = await getBusinessById(id);
      if (existing == null) {
        throw const AppException(
          AppErrorKind.notFound,
          'That business could not be found.',
        );
      }
      return existing;
    }

    final response = await Net.call(
      () => supabase
          .from('businesses')
          .update(payload)
          .eq('id', id)
          .select()
          .single(),
      whileDoing: 'update that business',
    );

    await _cache.remove('business_$id');
    await _cache.remove('all_businesses');
    return Business.fromJson(response);
  }

  /// Soft-deletes via an RPC that runs the whole thing in one transaction.
  ///
  /// The old version issued two independent statements: delete the reviews,
  /// then delete the business. If the second failed — offline, RLS, a
  /// cancelled request — the reviews were already gone and the business
  /// remained with a rating computed from nothing.
  Future<void> deleteBusiness(String id) async {
    await Net.call(
      () => supabase.rpc('soft_delete_business', params: {'p_business_id': id}),
      whileDoing: 'delete that business',
    );

    final userId = currentUserId;
    await _cache.remove('business_$id');
    await _cache.remove('all_businesses');
    if (userId != null) await _cache.remove('owner_businesses_$userId');
  }

  // ===========================================================================
  // Reviews
  // ===========================================================================

  Future<List<Review>> getBusinessReviews(String businessId,
      {int limit = 100}) async {
    try {
      final rows = await Net.call(
        () => supabase
            .from('reviews')
            .select()
            .eq('business_id', businessId)
            .order('created_at', ascending: false)
            .limit(limit),
        whileDoing: 'load reviews',
      );

      final list = (rows as List).cast<Map<String, dynamic>>();
      await _cache.save('reviews_$businessId', list);
      return list.map(Review.fromJson).toList();
    } on AppException catch (error) {
      if (error.kind != AppErrorKind.network) rethrow;
      final cached = await _cache.readList('reviews_$businessId');
      if (cached != null) return cached.map(Review.fromJson).toList();
      rethrow;
    }
  }

  Future<Review> addReview(Review review) async {
    final userId = _requireUserId;

    // user_name, user_email and is_verified_visit are stamped by a BEFORE
    // INSERT trigger from the session and the check_ins table. Sending them
    // was pointless at best and a way to fake a "verified visit" badge at
    // worst, so they are dropped here.
    final payload = review.toJson()
      ..['user_id'] = userId
      ..remove('user_name')
      ..remove('user_email')
      ..remove('is_verified_visit');

    try {
      final response = await Net.call(
        () => supabase.from('reviews').insert(payload).select().single(),
        whileDoing: 'post your review',
      );
      await _cache.remove('reviews_${review.businessId}');
      await _cache.remove('business_${review.businessId}');
      return Review.fromJson(response);
    } on AppException catch (error) {
      if (error.kind == AppErrorKind.duplicate) {
        throw const AppException(
          AppErrorKind.duplicate,
          'You have already reviewed this business. Edit your existing review instead.',
        );
      }
      rethrow;
    }
  }

  Future<void> replyToReview(String reviewId, String reply) async {
    final trimmed = reply.trim();
    if (trimmed.isEmpty) {
      throw const AppException(AppErrorKind.invalid, 'Write a reply first.');
    }

    await Net.call(
      // owner_reply_at is set by the guard trigger so the timestamp comes from
      // the server clock, not from a device whose clock may be wrong.
      () => supabase
          .from('reviews')
          .update({'owner_reply': trimmed}).eq('id', reviewId),
      whileDoing: 'post your reply',
    );
  }

  Future<void> deleteReviewReply(String reviewId) async {
    await Net.call(
      () => supabase
          .from('reviews')
          .update({'owner_reply': null}).eq('id', reviewId),
      whileDoing: 'remove your reply',
    );
  }

  /// Fills in likesCount / isLikedByMe. Non-critical: a failure leaves the
  /// counts at zero rather than blocking the review list.
  Future<void> populateReviewLikes(
      List<Review> reviews, String? currentUserId) async {
    if (reviews.isEmpty) return;

    final rows = await Net.callOr<List<dynamic>>(
      () async => await supabase
          .from('review_likes')
          .select('review_id, user_id')
          .inFilter('review_id', reviews.map((r) => r.id).toList()),
      const [],
    );

    final counts = <String, int>{};
    final likedByMe = <String>{};

    for (final like in rows) {
      final reviewId = like['review_id'] as String;
      counts[reviewId] = (counts[reviewId] ?? 0) + 1;
      if (currentUserId != null && like['user_id'] == currentUserId) {
        likedByMe.add(reviewId);
      }
    }

    for (final review in reviews) {
      review.likesCount = counts[review.id] ?? 0;
      review.isLikedByMe = likedByMe.contains(review.id);
    }
  }

  // ===========================================================================
  // Uploads
  // ===========================================================================

  Future<String> uploadBusinessImage(File imageFile) =>
      _uploadImage(imageFile, folder: 'businesses');

  Future<String> uploadReviewImage(File imageFile) =>
      _uploadImage(imageFile, folder: 'reviews');

  Future<String> uploadAvatarImage(File imageFile) =>
      _uploadImage(imageFile, folder: 'avatars');

  /// Uploads in parallel and returns public URLs in the same order.
  ///
  /// `Future.wait` rejects on the first error but leaves the other uploads
  /// running, so a partial failure used to strand orphaned objects in the
  /// bucket. Failures are collected instead, and anything that did succeed is
  /// cleaned up before the error is rethrown.
  Future<List<String>> uploadReviewImages(List<File> files) async {
    if (files.isEmpty) return const [];

    final results = await Future.wait(
      files.map((file) async {
        try {
          return await uploadReviewImage(file);
        } on AppException catch (error) {
          return error;
        }
      }),
    );

    final urls = results.whereType<String>().toList();
    final failures = results.whereType<AppException>().toList();

    if (failures.isNotEmpty) {
      final failure = failures.first;
      await _removeUploaded(urls);
      throw failure;
    }
    return urls;
  }

  Future<String> _uploadImage(File imageFile, {required String folder}) async {
    final userId = _requireUserId;
    final mime = await UploadValidator.validate(imageFile);
    final key = UploadValidator.storageKey(
      folder: folder,
      userId: userId,
      mime: mime,
    );

    await Net.call(
      () => supabase.storage.from('htbiz_images').upload(
            key,
            imageFile,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          ),
      timeout: Net.uploadTimeout,
      // Re-sending a whole image over a weak link is expensive; one retry.
      attempts: 2,
      whileDoing: 'upload that image',
    );

    return supabase.storage.from('htbiz_images').getPublicUrl(key);
  }

  Future<void> _removeUploaded(List<String> publicUrls) async {
    final keys =
        publicUrls.map(_storageKeyFromPublicUrl).whereType<String>().toList();
    if (keys.isEmpty) return;
    await Net.callOr<List<dynamic>>(
      () async => await supabase.storage.from('htbiz_images').remove(keys),
      const [],
    );
  }

  /// Recovers the storage key from a public URL.
  ///
  /// Supabase public URLs look like
  /// `.../storage/v1/object/public/htbiz_images/<key>`, so the key is
  /// everything after the bucket segment.
  static String? _storageKeyFromPublicUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments == null) return null;
    final index = segments.indexOf('htbiz_images');
    if (index == -1 || index >= segments.length - 1) return null;
    return segments.sublist(index + 1).map(Uri.decodeComponent).join('/');
  }

  // ===========================================================================
  // Profiles
  // ===========================================================================

  Future<UserProfile?> getProfile(String userId) async {
    try {
      final response = await Net.call(
        () => supabase.from('profiles').select().eq('id', userId).maybeSingle(),
        whileDoing: 'load your profile',
      );
      if (response == null) return null;
      await _cache.save('profile_$userId', response);
      return UserProfile.fromJson(response);
    } on AppException catch (error) {
      if (error.kind != AppErrorKind.network) rethrow;
      final cached = await _cache.readMap('profile_$userId');
      if (cached != null) return UserProfile.fromJson(cached);
      rethrow;
    }
  }

  Future<void> updateProfile({
    required String userId,
    required String email,
    String? fullName,
    String? avatarUrl,
    String? role,
  }) async {
    if (userId != _requireUserId) {
      throw const AppException(
        AppErrorKind.forbidden,
        'You can only edit your own profile.',
      );
    }
    if (role != null && role != 'client' && role != 'business_owner') {
      throw const AppException(AppErrorKind.invalid, 'That role is not valid.');
    }

    final data = <String, dynamic>{'id': userId, 'email': email};
    if (fullName != null) data['full_name'] = fullName;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (role != null) data['role'] = role;

    await Net.call(
      () => supabase.from('profiles').upsert(data),
      whileDoing: 'save your profile',
    );
    await _cache.remove('profile_$userId');
  }

  // ===========================================================================
  // Business gallery
  // ===========================================================================

  Future<List<BusinessImage>> getBusinessImages(String businessId) async {
    try {
      final rows = await Net.call(
        () => supabase
            .from('business_images')
            .select()
            .eq('business_id', businessId)
            .order('created_at', ascending: true)
            .limit(30),
        whileDoing: 'load photos',
      );
      final list = (rows as List).cast<Map<String, dynamic>>();
      await _cache.save('images_$businessId', list);
      return list.map(BusinessImage.fromJson).toList();
    } on AppException catch (error) {
      if (error.kind != AppErrorKind.network) rethrow;
      final cached = await _cache.readList('images_$businessId');
      if (cached != null) return cached.map(BusinessImage.fromJson).toList();
      rethrow;
    }
  }

  Future<BusinessImage> addBusinessImage(
      String businessId, File imageFile) async {
    final imageUrl = await _uploadImage(imageFile, folder: 'businesses');

    try {
      final response = await Net.call(
        () => supabase
            .from('business_images')
            .insert({'business_id': businessId, 'image_url': imageUrl})
            .select()
            .single(),
        whileDoing: 'save that photo',
      );
      await _cache.remove('images_$businessId');
      return BusinessImage.fromJson(response);
    } on AppException {
      // The file uploaded but the row did not insert — do not leave it behind.
      await _removeUploaded([imageUrl]);
      rethrow;
    }
  }

  Future<void> deleteBusinessImage(String imageId, String imageUrl) async {
    // Delete the row first. If storage removal fails we are left with an
    // orphaned object, which is invisible; the reverse order leaves a row
    // pointing at a 404, which the user sees as a broken image.
    await Net.call(
      () => supabase.from('business_images').delete().eq('id', imageId),
      whileDoing: 'delete that photo',
    );
    await _removeUploaded([imageUrl]);
  }

  // ===========================================================================
  // Favorites
  // ===========================================================================

  Future<Set<String>> getFavoriteIds(String userId) async {
    try {
      final rows = await Net.call(
        () => supabase
            .from('favorites')
            .select('business_id')
            .eq('user_id', userId),
        whileDoing: 'load your favourites',
      );
      final ids =
          (rows as List).map((r) => r['business_id'] as String).toList();
      await _cache.save('favorites_$userId', ids);
      return ids.toSet();
    } on AppException catch (error) {
      if (error.kind != AppErrorKind.network) rethrow;
      final cached = await _cache.readStringList('favorites_$userId');
      return cached?.toSet() ?? <String>{};
    }
  }

  /// Idempotent: double-tapping the heart no longer raises a unique violation.
  Future<void> addFavorite(String businessId) async {
    final userId = _requireUserId;
    await Net.call(
      () => supabase.from('favorites').upsert(
        {'user_id': userId, 'business_id': businessId},
        onConflict: 'user_id, business_id',
        ignoreDuplicates: true,
      ),
      whileDoing: 'save that favourite',
    );
    await _cache.remove('favorites_$userId');
  }

  Future<void> removeFavorite(String businessId) async {
    final userId = _requireUserId;
    await Net.call(
      () => supabase
          .from('favorites')
          .delete()
          .eq('user_id', userId)
          .eq('business_id', businessId),
      whileDoing: 'remove that favourite',
    );
    await _cache.remove('favorites_$userId');
  }

  Future<List<Business>> getFavoriteBusinesses(String userId) async {
    final favorites = await Net.call(
      () => supabase
          .from('favorites')
          .select('business_id')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(200),
      whileDoing: 'load your favourites',
    );

    final ids =
        (favorites as List).map((r) => r['business_id'] as String).toList();
    if (ids.isEmpty) return const [];

    final rows = await Net.call(
      () => supabase
          .from('businesses')
          .select()
          .inFilter('id', ids)
          .isFilter('deleted_at', null),
      whileDoing: 'load your favourites',
    );

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Business.fromJson)
        .toList();
  }

  // ===========================================================================
  // Notifications
  // ===========================================================================

  Future<List<AppNotification>> getNotifications(String userId) async {
    try {
      final rows = await Net.call(
        () => supabase
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(50),
        whileDoing: 'load notifications',
      );
      final list = (rows as List).cast<Map<String, dynamic>>();
      await _cache.save('notifications_$userId', list);
      return list.map(AppNotification.fromJson).toList();
    } on AppException catch (error) {
      if (error.kind != AppErrorKind.network) rethrow;
      final cached = await _cache.readList('notifications_$userId');
      if (cached != null) return cached.map(AppNotification.fromJson).toList();
      rethrow;
    }
  }

  /// Counted in the database.
  ///
  /// The previous version selected every unread row and took `.length` — which
  /// downloads the whole set to render a badge, and silently caps at
  /// `max_rows` so a busy owner's badge would stick at 1000.
  Future<int> getUnreadNotificationCount(String userId) async {
    return Net.callOr<int>(
      () async =>
          ((await supabase.rpc('unread_notification_count')) as num?)
              ?.toInt() ??
          0,
      0,
    );
  }

  Future<void> markNotificationRead(String notificationId) async {
    await Net.call(
      () => supabase
          .from('notifications')
          .update({'is_read': true}).eq('id', notificationId),
      whileDoing: 'update that notification',
    );
  }

  Future<void> markAllNotificationsRead(String userId) async {
    await Net.call(
      () => supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false),
      whileDoing: 'update your notifications',
    );
    await _cache.remove('notifications_$userId');
  }

  // ===========================================================================
  // Owner analytics
  // ===========================================================================

  Future<List<Business>> getOwnerBusinesses(String ownerId) async {
    try {
      final rows = await Net.call(
        () => supabase
            .from('businesses')
            .select()
            .eq('owner_id', ownerId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(100),
        whileDoing: 'load your businesses',
      );
      final list = (rows as List).cast<Map<String, dynamic>>();
      await _cache.save('owner_businesses_$ownerId', list);
      return list.map(Business.fromJson).toList();
    } on AppException catch (error) {
      if (error.kind != AppErrorKind.network) rethrow;
      final cached = await _cache.readList('owner_businesses_$ownerId');
      if (cached != null) return cached.map(Business.fromJson).toList();
      rethrow;
    }
  }

  /// Favourites, check-ins, review count and average rating in one round trip.
  ///
  /// These counts cannot be taken from the client: `favorites` is select-own
  /// under RLS, so an owner querying `favorites` for their own business always
  /// got back an empty list and the dashboard showed 0. The RPC counts them
  /// server-side after checking the caller owns the business.
  Future<BusinessStats> getBusinessStats(String businessId) async {
    final rows = await Net.callOr<List<dynamic>>(
      () async => (await supabase.rpc('business_stats',
          params: {'p_business_id': businessId})) as List<dynamic>,
      const [],
    );

    if (rows.isEmpty) return const BusinessStats.empty();
    return BusinessStats.fromJson((rows.first as Map).cast<String, dynamic>());
  }

  Future<int> getFavoriteCount(String businessId) async =>
      (await getBusinessStats(businessId)).favoriteCount;

  Future<Map<int, int>> getRatingDistribution(String businessId) async {
    final distribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    try {
      for (final review in await getBusinessReviews(businessId)) {
        // Guard the bucket lookup: a rating outside 1..5 from legacy data
        // would otherwise add a stray key the chart cannot render.
        if (distribution.containsKey(review.rating)) {
          distribution[review.rating] = distribution[review.rating]! + 1;
        }
      }
    } on AppException {
      // An empty distribution renders an empty chart, which is correct.
    }
    return distribution;
  }

  // ===========================================================================
  // Review likes
  // ===========================================================================

  Future<void> likeReview(String reviewId) async {
    final userId = _requireUserId;
    await Net.call(
      () => supabase.from('review_likes').upsert(
        {'review_id': reviewId, 'user_id': userId},
        onConflict: 'review_id, user_id',
        ignoreDuplicates: true,
      ),
      whileDoing: 'save that like',
    );
  }

  Future<void> unlikeReview(String reviewId) async {
    final userId = _requireUserId;
    await Net.call(
      () => supabase
          .from('review_likes')
          .delete()
          .eq('review_id', reviewId)
          .eq('user_id', userId),
      whileDoing: 'remove that like',
    );
  }

  // ===========================================================================
  // Verification
  // ===========================================================================

  /// Uploads to the PRIVATE bucket and returns the storage key, never a URL.
  Future<String> uploadPatentDocument(File file) async {
    final userId = _requireUserId;
    final mime = await UploadValidator.validate(file, allowPdf: true);

    // The patents bucket policy keys off the FIRST path segment, so this key
    // is intentionally `<uid>/<file>` rather than `<folder>/<uid>/<file>`.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final extension = mime == 'application/pdf' ? '.pdf' : '.jpg';
    final key = '$userId/$stamp$extension';

    await Net.call(
      () => supabase.storage.from('htbiz_patents').upload(
            key,
            file,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          ),
      timeout: Net.uploadTimeout,
      attempts: 2,
      whileDoing: 'upload that document',
    );

    return key;
  }

  Future<String> getPatentSignedUrl(String storagePath) async {
    return Net.call(
      () => supabase.storage
          .from('htbiz_patents')
          .createSignedUrl(storagePath, 300),
      whileDoing: 'open that document',
    );
  }

  Future<void> submitVerification(
      String businessId, String patentStoragePath) async {
    await Net.call(
      () => supabase.from('businesses').update({
        'patent_doc_url': patentStoragePath,
        'verification_status': 'pending',
      }).eq('id', businessId),
      whileDoing: 'submit your documents',
    );
    await _cache.remove('business_$businessId');
  }

  // ===========================================================================
  // Check-ins
  // ===========================================================================

  Future<void> checkInToBusiness(String businessId) async {
    final userId = _requireUserId;
    await Net.call(
      () => supabase.from('check_ins').upsert(
        {'user_id': userId, 'business_id': businessId},
        onConflict: 'user_id, business_id',
        ignoreDuplicates: true,
      ),
      whileDoing: 'check in',
    );
  }

  Future<bool> hasCheckedIn(String userId, String businessId) async {
    final rows = await Net.callOr<List<dynamic>>(
      () async => await supabase
          .from('check_ins')
          .select('id')
          .eq('user_id', userId)
          .eq('business_id', businessId)
          .limit(1),
      const [],
    );
    return rows.isNotEmpty;
  }

  // ===========================================================================
  // Location helpers
  // ===========================================================================

  /// Great-circle distance in kilometres.
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    // clamp guards against a floating-point a marginally above 1, which makes
    // sqrt(1 - a) NaN and poisons every distance-sorted list.
    final c = 2 * atan2(sqrt(a.clamp(0.0, 1.0)), sqrt((1 - a).clamp(0.0, 1.0)));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}

/// Aggregates returned by the `business_stats` RPC.
class BusinessStats {
  const BusinessStats({
    required this.favoriteCount,
    required this.checkInCount,
    required this.reviewCount,
    required this.averageRating,
  });

  const BusinessStats.empty()
      : favoriteCount = 0,
        checkInCount = 0,
        reviewCount = 0,
        averageRating = 0;

  final int favoriteCount;
  final int checkInCount;
  final int reviewCount;
  final double averageRating;

  factory BusinessStats.fromJson(Map<String, dynamic> json) => BusinessStats(
        favoriteCount: (json['favorite_count'] as num?)?.toInt() ?? 0,
        checkInCount: (json['check_in_count'] as num?)?.toInt() ?? 0,
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
        averageRating: (json['average_rating'] as num?)?.toDouble() ?? 0,
      );
}
