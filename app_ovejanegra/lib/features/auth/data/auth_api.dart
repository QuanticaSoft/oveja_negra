import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/auth_user.dart';

/// Endpoints de `/auth`. Login, refresh y logout son públicos y van por [_public] (sin el
/// interceptor de sesión); `/me` y el cambio de contraseña van por [_authed].
class AuthApi {
  AuthApi(this._public, this._authed);

  final Dio _public;
  final Dio _authed;

  Future<Session> login(String identifier, String password) => apiCall(
        () => _public.post<dynamic>('/auth/login', data: {'identifier': identifier, 'password': password}),
        (data) => Session.fromJson(data as Map<String, dynamic>),
      );

  Future<Session> refresh(String refreshToken) => apiCall(
        () => _public.post<dynamic>('/auth/refresh', data: {'refresh_token': refreshToken}),
        (data) => Session.fromJson(data as Map<String, dynamic>),
      );

  Future<void> logout(String refreshToken) => apiCall(
        () => _public.post<dynamic>('/auth/logout', data: {'refresh_token': refreshToken}),
        (_) {},
      );

  Future<AuthUser> me() => apiCall(
        () => _authed.get<dynamic>('/auth/me'),
        (data) => AuthUser.fromJson(data as Map<String, dynamic>),
      );

  /// Revoca todas las sesiones y devuelve una nueva.
  Future<Session> changePassword(String current, String next) => apiCall(
        () => _authed.patch<dynamic>('/auth/me/password', data: {'current_password': current, 'new_password': next}),
        (data) => Session.fromJson(data as Map<String, dynamic>),
      );
}
