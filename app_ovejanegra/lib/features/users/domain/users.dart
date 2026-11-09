class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.phone,
    this.lastLoginAt,
  });

  final int id;
  final String username;
  final String fullName;
  final String? phone;
  final String role;
  final bool isActive;
  final String? lastLoginAt;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as int,
        username: j['username'] as String,
        fullName: j['full_name'] as String,
        phone: j['phone'] as String?,
        role: j['role'] as String,
        isActive: j['is_active'] as bool,
        lastLoginAt: j['last_login_at'] as String?,
      );
}

class Role {
  const Role({required this.id, required this.code, required this.name, required this.permissions});

  /// Permisos que el ADMIN conserva siempre (el backend rechaza quitarlos con 409).
  static const adminRequired = {'users.manage', 'roles.manage'};

  final int id;
  final String code;
  final String name;
  final Set<String> permissions;

  factory Role.fromJson(Map<String, dynamic> j) => Role(
        id: j['id'] as int,
        code: j['code'] as String,
        name: j['name'] as String,
        permissions: {...(j['permissions'] as List).cast<String>()},
      );
}

class Permission {
  const Permission(this.code, this.description);

  final String code;
  final String description;

  /// "orders.create" → "orders": agrupa la matriz por módulo.
  String get module => code.split('.').first;

  factory Permission.fromJson(Map<String, dynamic> j) => Permission(j['code'] as String, j['description'] as String);
}
