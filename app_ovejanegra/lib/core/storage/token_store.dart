import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Donde vive el refresh token entre aperturas de la app. Interfaz propia para poder usar un
/// doble en memoria en los tests.
abstract interface class RefreshTokenStorage {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureRefreshTokenStorage implements RefreshTokenStorage {
  const SecureRefreshTokenStorage([this._storage = const FlutterSecureStorage()]);

  static const _key = 'refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// El access token (15 min) solo en memoria; el refresh token (7 días, un solo uso) cifrado en el
/// dispositivo. Así un volcado del almacenamiento no entrega un token listo para usar.
class TokenStore {
  TokenStore(this._storage);

  final RefreshTokenStorage _storage;
  String? accessToken;

  Future<String?> refreshToken() => _storage.read();

  Future<void> save({required String accessToken, required String refreshToken}) async {
    this.accessToken = accessToken;
    await _storage.write(refreshToken);
  }

  Future<void> clear() async {
    accessToken = null;
    await _storage.delete();
  }
}
