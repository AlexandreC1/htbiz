class UserProfile {
  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final String role; // 'client' or 'business_owner'
  final DateTime createdAt;

  UserProfile({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.role = 'client',
    required this.createdAt,
  });

  bool get isBusinessOwner => role == 'business_owner';

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String? ?? 'client',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'role': role,
    };
  }
}
