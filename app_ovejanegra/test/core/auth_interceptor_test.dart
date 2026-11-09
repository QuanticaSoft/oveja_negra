import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ovejanegra/core/network/api_exception.dart';
import 'package:ovejanegra/core/network/auth_interceptor.dart';
import 'package:ovejanegra/core/storage/token_store.dart';
import 'package:ovejanegra/features/auth/data/auth_api.dart';
import 'package:ovejanegra/features/auth/domain/auth_user.dart';

import '../support/fakes.dart';

/// Servidor falso: solo acepta el access token vigente; cada refresh rota el par de tokens y
/// rechaza un refresh token ya usado, igual que el backend real.
class FakeServer {
  String validAccess = 'access-1';
  String validRefresh = 'refresh-1';
  int refreshCalls = 0;
  bool refreshFails = false;

  Future<FakeResponse> handle(RequestOptions o) async {
    if (o.path == '/auth/refresh') {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (refreshFails || (o.data as Map)['refresh_token'] != validRefresh) {
        return (401, errorJson('INVALID_REFRESH_TOKEN'));
      }
      validAccess = 'access-${refreshCalls + 1}';
      validRefresh = 'refresh-${refreshCalls + 1}';
      return (200, sessionJson(validAccess, validRefresh));
    }
    if (o.headers[AuthInterceptor.header] != validAccess) {
      return (401, errorJson('UNAUTHENTICATED'));
    }
    return (200, {'data': {'path': o.path}});
  }
}

void main() {
  late FakeServer server;
  late TokenStore tokens;
  late Dio dio;
  late int expired;
  late List<Session> refreshed;

  setUp(() async {
    server = FakeServer();
    tokens = TokenStore(MemoryRefreshTokenStorage('refresh-1'));
    tokens.accessToken = 'access-1';
    expired = 0;
    refreshed = [];
    final adapter = FakeAdapter(server.handle);
    final public = Dio(BaseOptions(baseUrl: 'http://api.test/v1'))..httpClientAdapter = adapter;
    dio = Dio(BaseOptions(baseUrl: 'http://api.test/v1'))..httpClientAdapter = adapter;
    final interceptor = AuthInterceptor(
      tokens: tokens,
      refresh: (rt) => AuthApi(public, dio).refresh(rt),
      onRefreshed: refreshed.add,
      onExpired: () => expired++,
    )..dio = dio;
    dio.interceptors.add(interceptor);
  });

  Future<dynamic> get(String path) => apiCall(() => dio.get<dynamic>(path), (data) => data);

  test('manda X-Auth-Token en cada petición', () async {
    expect(await get('/a'), {'path': '/a'});
  });

  test('varias peticiones con el token vencido hacen UN solo refresh y todas se reintentan', () async {
    server.validAccess = 'access-vencido-en-el-servidor';
    server.validRefresh = 'refresh-1';
    // El servidor emitirá access-2 al refrescar: el token viejo deja de servir.
    final results = await Future.wait([get('/a'), get('/b'), get('/c'), get('/d')]);

    expect(server.refreshCalls, 1);
    expect(results.map((r) => (r as Map)['path']), ['/a', '/b', '/c', '/d']);
    expect(tokens.accessToken, 'access-2');
    expect(await tokens.refreshToken(), 'refresh-2');
    expect(refreshed.length, 1);
    expect(expired, 0);
  });

  test('si el refresh es inválido la sesión termina y se borran los tokens', () async {
    server.validAccess = 'otro';
    server.refreshFails = true;

    await expectLater(get('/a'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHENTICATED')));
    expect(expired, 1);
    expect(tokens.accessToken, isNull);
    expect(await tokens.refreshToken(), isNull);
  });

  test('un 401 que no es de token vencido no dispara refresh', () async {
    final adapter = FakeAdapter((_) async => (401, errorJson('INVALID_CREDENTIALS')));
    dio.httpClientAdapter = adapter;
    await expectLater(get('/a'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_CREDENTIALS')));
    expect(server.refreshCalls, 0);
    expect(expired, 0);
  });

  test('USER_INACTIVE cierra la sesión sin intentar refresh', () async {
    dio.httpClientAdapter = FakeAdapter((_) async => (401, errorJson('USER_INACTIVE')));
    await expectLater(get('/a'), throwsA(isA<ApiException>()));
    expect([server.refreshCalls, expired], [0, 1]);
  });

  test('sin red el error es NETWORK_ERROR y la sesión sigue', () async {
    dio.httpClientAdapter = FakeAdapter((o) => Future.error(DioException.connectionError(requestOptions: o, reason: 'offline')));
    await expectLater(get('/a'), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)));
    expect(expired, 0);
    expect(await tokens.refreshToken(), 'refresh-1');
  });
}
