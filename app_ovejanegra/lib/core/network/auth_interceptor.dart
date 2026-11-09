import 'dart:async';

import 'package:dio/dio.dart';

import '../../features/auth/domain/auth_user.dart';
import '../storage/token_store.dart';
import 'api_exception.dart';

/// Agrega `X-Auth-Token` (PHP-FPM no reenvía `Authorization`) y, si el access token venció, hace
/// **un solo refresh a la vez**: el refresh token es de un solo uso y reusarlo revoca todas las
/// sesiones del usuario, así que las peticiones que fallan juntas esperan el mismo refresh y se
/// reintentan con el token nuevo.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokens,
    required this.refresh,
    required this.onRefreshed,
    required this.onExpired,
  });

  static const header = 'X-Auth-Token';
  static const _retried = 'auth_retried';

  final TokenStore tokens;
  final Future<Session> Function(String refreshToken) refresh;
  final void Function(Session session) onRefreshed;
  final void Function() onExpired;

  /// La instancia de Dio que reintenta; se asigna al registrar el interceptor.
  late Dio dio;
  Future<String?>? _refreshing;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokens.accessToken;
    if (token != null) {
      options.headers[header] = token;
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final code = _errorCode(err);
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[_retried] == true) {
      return handler.next(err);
    }
    if (code == 'USER_INACTIVE') {
      await _expire();
      return handler.next(err);
    }
    if (code != 'UNAUTHENTICATED') {
      return handler.next(err);
    }

    final String? newToken;
    try {
      final sent = options.headers[header];
      // Si otra petición ya renovó el token mientras esta viajaba, se reintenta directo con él.
      newToken = tokens.accessToken != null && tokens.accessToken != sent
          ? tokens.accessToken
          : await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    } on ApiException catch (e) {
      return handler.next(DioException(requestOptions: options, response: err.response, error: e));
    }
    if (newToken == null) {
      return handler.next(err);
    }

    options
      ..headers[header] = newToken
      ..extra[_retried] = true;
    try {
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Devuelve el access token nuevo, o null si la sesión terminó (refresh inválido o inexistente).
  /// Un error de red se relanza sin cerrar la sesión: el refresh token sigue sirviendo.
  Future<String?> _refresh() async {
    final refreshToken = await tokens.refreshToken();
    if (refreshToken == null) {
      await _expire();
      return null;
    }
    try {
      final session = await refresh(refreshToken);
      await tokens.save(accessToken: session.accessToken, refreshToken: session.refreshToken);
      onRefreshed(session);
      return session.accessToken;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        rethrow;
      }
      await _expire();
      return null;
    }
  }

  Future<void> _expire() async {
    await tokens.clear();
    onExpired();
  }

  static String? _errorCode(DioException err) {
    final data = err.response?.data;
    return data is Map && data['error'] is Map ? (data['error'] as Map)['code'] as String? : null;
  }
}
