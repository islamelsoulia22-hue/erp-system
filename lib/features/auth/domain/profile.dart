/// Lightweight profile model (mirrors public.profiles).
class Profile {
  final String id;
  final String fullName;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final bool isActive;

  const Profile({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.avatarUrl,
    required this.isActive,
  });

  factory Profile.fromMap(Map<String, dynamic> m) {
    return Profile(
      id: m['id'] as String,
      fullName: (m['full_name'] as String?) ?? '',
      phone: m['phone'] as String?,
      email: m['email'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      isActive: (m['is_active'] as bool?) ?? true,
    );
  }
}

/// Role row (public.roles).
class Role {
  final String id;
  final String key;
  final String nameAr;

  const Role({required this.id, required this.key, required this.nameAr});

  factory Role.fromMap(Map<String, dynamic> m) {
    return Role(
      id: m['id'] as String,
      key: m['key'] as String,
      nameAr: (m['name_ar'] as String?) ?? m['key'] as String,
    );
  }
}
