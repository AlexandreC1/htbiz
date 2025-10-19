class Business {
  final String id;
  final String name;
  final String description;
  final String category;
  final String address;
  final String? phone;
  final String? imageUrl;
  final double rating;
  final int totalReviews;
  final String ownerId;
  final DateTime createdAt;

  Business({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.address,
    this.phone,
    this.imageUrl,
    required this.rating,
    required this.totalReviews,
    required this.ownerId,
    required this.createdAt,
  });

  // Convert from Supabase JSON to Business object
  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      category: json['category'] as String,
      address: json['address'] as String,
      phone: json['phone'] as String?,
      imageUrl: json['image_url'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      totalReviews: json['total_reviews'] as int? ?? 0,
      ownerId: json['owner_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  // Convert Business object to JSON for Supabase
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'category': category,
      'address': address,
      'phone': phone,
      'image_url': imageUrl,
      'rating': rating,
      'total_reviews': totalReviews,
      'owner_id': ownerId,
    };
  }

  // Create a copy with updated fields
  Business copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    String? address,
    String? phone,
    String? imageUrl,
    double? rating,
    int? totalReviews,
    String? ownerId,
    DateTime? createdAt,
  }) {
    return Business(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      imageUrl: imageUrl ?? this.imageUrl,
      rating: rating ?? this.rating,
      totalReviews: totalReviews ?? this.totalReviews,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
