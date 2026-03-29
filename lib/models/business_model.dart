class Business {
  final String id;
  final String name;
  final String description;
  final String category;
  final String address;
  final String? phone;
  final String? whatsapp;
  final String? website;
  final String? hoursText;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final double rating;
  final int totalReviews;
  final String ownerId;
  final DateTime createdAt;
  final String verificationStatus; // 'none', 'pending', 'verified', 'rejected'
  final String? patentDocUrl;

  Business({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.address,
    this.phone,
    this.whatsapp,
    this.website,
    this.hoursText,
    this.latitude,
    this.longitude,
    this.imageUrl,
    required this.rating,
    required this.totalReviews,
    required this.ownerId,
    required this.createdAt,
    this.verificationStatus = 'none',
    this.patentDocUrl,
  });

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      category: json['category'] as String,
      address: json['address'] as String,
      phone: json['phone'] as String?,
      whatsapp: json['whatsapp'] as String?,
      website: json['website'] as String?,
      hoursText: json['hours_text'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      totalReviews: json['total_reviews'] as int? ?? 0,
      ownerId: json['owner_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      verificationStatus: json['verification_status'] as String? ?? 'none',
      patentDocUrl: json['patent_doc_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'description': description,
      'category': category,
      'address': address,
      'phone': phone,
      'whatsapp': whatsapp,
      'website': website,
      'hours_text': hoursText,
      'image_url': imageUrl,
      'rating': rating,
      'total_reviews': totalReviews,
      'owner_id': ownerId,
    };
    if (latitude != null) map['latitude'] = latitude;
    if (longitude != null) map['longitude'] = longitude;
    if (verificationStatus != 'none') map['verification_status'] = verificationStatus;
    if (patentDocUrl != null) map['patent_doc_url'] = patentDocUrl;
    return map;
  }

  Business copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    String? address,
    String? phone,
    String? whatsapp,
    String? website,
    String? hoursText,
    double? latitude,
    double? longitude,
    String? imageUrl,
    double? rating,
    int? totalReviews,
    String? ownerId,
    DateTime? createdAt,
    String? verificationStatus,
    String? patentDocUrl,
  }) {
    return Business(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      whatsapp: whatsapp ?? this.whatsapp,
      website: website ?? this.website,
      hoursText: hoursText ?? this.hoursText,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageUrl: imageUrl ?? this.imageUrl,
      rating: rating ?? this.rating,
      totalReviews: totalReviews ?? this.totalReviews,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      patentDocUrl: patentDocUrl ?? this.patentDocUrl,
    );
  }
}
