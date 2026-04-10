class Review {
  final String id;
  final String businessId;
  final String userId;
  final int rating;
  final String? comment;
  /// Legacy single image (still populated by the DB trigger/backfill for old rows).
  final String? imageUrl;
  /// New: multiple images per review. Empty list if none.
  final List<String> imageUrls;
  final String? ownerReply;
  final DateTime? ownerReplyAt;
  final DateTime createdAt;
  final bool isVerifiedVisit;

  String? userName;
  String? userEmail;

  // Client-side state (populated after fetch)
  int likesCount;
  bool isLikedByMe;

  Review({
    required this.id,
    required this.businessId,
    required this.userId,
    required this.rating,
    this.comment,
    this.imageUrl,
    this.imageUrls = const [],
    this.ownerReply,
    this.ownerReplyAt,
    required this.createdAt,
    this.isVerifiedVisit = false,
    this.userName,
    this.userEmail,
    this.likesCount = 0,
    this.isLikedByMe = false,
  });

  /// Returns the combined list of image URLs: new image_urls first, falling back
  /// to the legacy image_url if the array is empty. Always safe to iterate.
  List<String> get allImages {
    if (imageUrls.isNotEmpty) return imageUrls;
    if (imageUrl != null && imageUrl!.isNotEmpty) return [imageUrl!];
    return const [];
  }

  factory Review.fromJson(Map<String, dynamic> json) {
    List<String> parsedImages = const [];
    final rawImages = json['image_urls'];
    if (rawImages is List) {
      parsedImages = rawImages.whereType<String>().toList();
    }
    return Review(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      userId: json['user_id'] as String,
      rating: json['rating'] as int,
      comment: json['comment'] as String?,
      imageUrl: json['image_url'] as String?,
      imageUrls: parsedImages,
      ownerReply: json['owner_reply'] as String?,
      ownerReplyAt: json['owner_reply_at'] != null
          ? DateTime.parse(json['owner_reply_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      isVerifiedVisit: json['is_verified_visit'] as bool? ?? false,
      userName: json['user_name'] as String?,
      userEmail: json['user_email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'user_id': userId,
      'rating': rating,
      'comment': comment,
      'image_url': imageUrls.isNotEmpty ? imageUrls.first : imageUrl,
      'image_urls': imageUrls,
      'is_verified_visit': isVerifiedVisit,
      'user_name': userName,
      'user_email': userEmail,
    };
  }

  Review copyWith({
    String? id,
    String? businessId,
    String? userId,
    int? rating,
    String? comment,
    String? imageUrl,
    List<String>? imageUrls,
    String? ownerReply,
    DateTime? ownerReplyAt,
    DateTime? createdAt,
    bool? isVerifiedVisit,
    String? userName,
    String? userEmail,
    int? likesCount,
    bool? isLikedByMe,
  }) {
    return Review(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      userId: userId ?? this.userId,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      ownerReply: ownerReply ?? this.ownerReply,
      ownerReplyAt: ownerReplyAt ?? this.ownerReplyAt,
      createdAt: createdAt ?? this.createdAt,
      isVerifiedVisit: isVerifiedVisit ?? this.isVerifiedVisit,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      likesCount: likesCount ?? this.likesCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
    );
  }
}
