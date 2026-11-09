import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/users.dart';

class UsersApi {
  UsersApi(this._dio);

  final Dio _dio;

  Future<List<AppUser>> users() => apiCall(
        () => _dio.get<dynamic>('/users', queryParameters: {'per_page': 100}),
        (data) => [for (final u in data as List) AppUser.fromJson(u as Map<String, dynamic>)],
      );

  Future<void> create(Map<String, dynamic> fields) => apiCall(() => _dio.post<dynamic>('/users', data: fields), (_) {});

  Future<void> update(int id, Map<String, dynamic> fields) =>
      apiCall(() => _dio.patch<dynamic>('/users/$id', data: fields), (_) {});

  Future<void> setActive(int id, bool active) =>
      apiCall(() => _dio.patch<dynamic>('/users/$id/status', data: {'is_active': active}), (_) {});

  Future<void> resetPassword(int id, String password) =>
      apiCall(() => _dio.patch<dynamic>('/users/$id/password', data: {'new_password': password}), (_) {});

  Future<List<Role>> roles() => apiCall(
        () => _dio.get<dynamic>('/roles'),
        (data) => [for (final r in data as List) Role.fromJson(r as Map<String, dynamic>)],
      );

  Future<List<Permission>> permissions() => apiCall(
        () => _dio.get<dynamic>('/permissions'),
        (data) => [for (final p in data as List) Permission.fromJson(p as Map<String, dynamic>)],
      );

  /// Reemplaza el conjunto completo de permisos del rol.
  Future<void> replacePermissions(int roleId, Set<String> permissions) => apiCall(
        () => _dio.put<dynamic>('/roles/$roleId/permissions', data: {'permissions': permissions.toList()..sort()}),
        (_) {},
      );
}
