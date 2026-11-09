import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ovejanegra/core/storage/token_store.dart';

/// Respuesta de un handler del adaptador falso: (status, cuerpo JSON).
typedef FakeResponse = (int, Map<String, dynamic>);

/// Adaptador HTTP en memoria: cada petición se resuelve con [handler], sin red.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Future<FakeResponse> Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = await handler(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class MemoryRefreshTokenStorage implements RefreshTokenStorage {
  MemoryRefreshTokenStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

Map<String, dynamic> userJson({List<String> permissions = const ['orders.create'], String role = 'CAJERO'}) => {
      'id': 7,
      'username': 'caja1',
      'full_name': 'Caja Uno',
      'role': role,
      'permissions': permissions,
    };

Map<String, dynamic> sessionJson(String access, String refresh, {List<String> permissions = const ['orders.create']}) => {
      'data': {
        'access_token': access,
        'expires_in': 900,
        'refresh_token': refresh,
        'user': userJson(permissions: permissions),
      },
    };

Map<String, dynamic> errorJson(String code, [String message = 'Error']) => {
      'error': {'code': code, 'message': message},
    };
