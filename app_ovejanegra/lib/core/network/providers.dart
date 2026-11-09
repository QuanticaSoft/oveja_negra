import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_api.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../config/env.dart';
import '../storage/token_store.dart';
import 'auth_interceptor.dart';

BaseOptions _options() => BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );

/// Adaptador HTTP de las dos instancias de Dio. null = el real; los tests ponen uno en memoria.
final httpAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

Dio _dio(Ref ref) {
  final dio = Dio(_options());
  final adapter = ref.watch(httpAdapterProvider);
  if (adapter != null) {
    dio.httpClientAdapter = adapter;
  }
  return dio;
}

final refreshTokenStorageProvider = Provider<RefreshTokenStorage>((ref) => const SecureRefreshTokenStorage());

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore(ref.watch(refreshTokenStorageProvider)));

/// Sin interceptor de sesión: para login, refresh y logout.
final publicDioProvider = Provider<Dio>(_dio);

/// Para todo lo que requiere sesión. El interceptor avisa al [SessionController] cuando la sesión
/// se renueva (permisos actualizados) o termina (la app vuelve al login).
final apiDioProvider = Provider<Dio>((ref) {
  final dio = _dio(ref);
  final interceptor = AuthInterceptor(
    tokens: ref.watch(tokenStoreProvider),
    refresh: (refreshToken) => AuthApi(ref.read(publicDioProvider), dio).refresh(refreshToken),
    onRefreshed: (session) => ref.read(sessionControllerProvider.notifier).sessionRefreshed(session),
    onExpired: () => ref.read(sessionControllerProvider.notifier).sessionExpired(),
  )..dio = dio;
  dio.interceptors.add(interceptor);
  return dio;
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(publicDioProvider), ref.watch(apiDioProvider)));
