class AppNotification {
  final String id;
  final String userId;
  final String type; // 'new_review', 'review_reply'
  final String title;
  final String body;
  final String? businessId;
  final String? reviewId;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.businessId,
    this.reviewId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      businessId: json['business_id'] as String?,
      reviewId: json['review_id'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  AppNotification copyWith({
    bool? isRead,
  }) {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      businessId: businessId,
      reviewId: reviewId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'type': type,
      'title': title,
      'body': body,
      'business_id': businessId,
      'review_id': reviewId,
      'is_read': isRead,
    };
  }
}
