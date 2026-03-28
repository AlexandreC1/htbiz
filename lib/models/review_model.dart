class Review {
  final String id;
  final String businessId;
  final String userId;
  final int rating;
  final String? comment;
  final String? imageUrl;
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
    this.ownerReply,
    this.ownerReplyAt,
    required this.createdAt,
    this.isVerifiedVisit = false,
    this.userName,
    this.userEmail,
    this.likesCount = 0,
    this.isLikedByMe = false,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      userId: json['user_id'] as String,
      rating: json['rating'] as int,
      comment: json['comment'] as String?,
      imageUrl: json['image_url'] as String?,
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
      'image_url': imageUrl,
      'is_verified_visit': isVerifiedVisit,
    };
  }

  Review copyWith({
    String? id,
    String? businessId,
    String? userId,
    int? rating,
    String? comment,
    String? imageUrl,
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
