class BusinessImage {
  final String id;
  final String businessId;
  final String imageUrl;
  final DateTime createdAt;

  BusinessImage({
    required this.id,
    required this.businessId,
    required this.imageUrl,
    required this.createdAt,
  });

  factory BusinessImage.fromJson(Map<String, dynamic> json) {
    return BusinessImage(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      imageUrl: json['image_url'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
