class Review {
  final String id;
  final String businessId;
  final String userId;
  final int rating;
  final String? comment;
  final String? imageUrl; // Added image support
  final DateTime createdAt;

  // Optional: user info for display
  String? userName;
  String? userEmail;

  Review({
    required this.id,
    required this.businessId,
    required this.userId,
    required this.rating,
    this.comment,
    this.imageUrl, // Added image parameter
    required this.createdAt,
    this.userName,
    this.userEmail,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      userId: json['user_id'] as String,
      rating: json['rating'] as int,
      comment: json['comment'] as String?,
      imageUrl: json['image_url'] as String?, // Added image field parsing
      createdAt: DateTime.parse(json['created_at'] as String),
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
      'image_url': imageUrl, // Added image field to serialization
    };
  }

  // Copy with method for creating modified copies
  Review copyWith({
    String? id,
    String? businessId,
    String? userId,
    int? rating,
    String? comment,
    String? imageUrl,
    DateTime? createdAt,
    String? userName,
    String? userEmail,
  }) {
    return Review(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      userId: userId ?? this.userId,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
    );
  }
}
