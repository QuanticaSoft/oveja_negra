/// Usuario de la sesión, tal como lo devuelve el API (`/auth/me`, login, refresh).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.permissions,
  });

  final int id;
  final String username;
  final String fullName;
  final String role;
  final Set<String> permissions;

  /// La app decide qué mostrar por **permiso**, nunca por nombre de rol (los permisos se pueden
  /// reasignar sin tocar código). El backend vuelve a validar siempre.
  bool can(String permission) => permissions.contains(permission);

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as int,
        username: json['username'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
        permissions: {...(json['permissions'] as List).cast<String>()},
      );
}

/// Respuesta de login, refresh y cambio de contraseña.
class Session {
  const Session({required this.accessToken, required this.refreshToken, required this.user});

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}
