import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/providers.dart';
import '../domain/auth_user.dart';

/// Usuario de la sesión actual, o null si no hay sesión. Al abrir la app intenta restaurar la
/// sesión con el refresh token guardado. El router redirige según este estado.
class SessionController extends AsyncNotifier<AuthUser?> {
  /// Por qué terminó la última sesión, para explicarlo en el login.
  String? endedReason;

  @override
  Future<AuthUser?> build() async {
    final tokens = ref.read(tokenStoreProvider);
    final refreshToken = await tokens.refreshToken();
    if (refreshToken == null) {
      return null;
    }
    try {
      final session = await ref.read(authApiProvider).refresh(refreshToken);
      await tokens.save(accessToken: session.accessToken, refreshToken: session.refreshToken);
      return session.user;
    } on ApiException catch (e) {
      // Sin red se muestra el error (con reintento) en vez de cerrar una sesión que sigue siendo válida.
      if (e.isNetwork) {
        rethrow;
      }
      await tokens.clear();
      return null;
    }
  }

  Future<void> login(String identifier, String password) async {
    final session = await ref.read(authApiProvider).login(identifier, password);
    await _start(session);
  }

  Future<void> changePassword(String current, String next) async {
    final session = await ref.read(authApiProvider).changePassword(current, next);
    await _start(session);
  }

  Future<void> logout() async {
    final tokens = ref.read(tokenStoreProvider);
    final refreshToken = await tokens.refreshToken();
    if (refreshToken != null) {
      try {
        await ref.read(authApiProvider).logout(refreshToken);
      } on ApiException {
        // Sin red igual se cierra la sesión local; el refresh token vence solo en 7 días.
      }
    }
    await tokens.clear();
    endedReason = null;
    state = const AsyncData(null);
  }

  void sessionRefreshed(Session session) => state = AsyncData(session.user);

  void sessionExpired() {
    endedReason = 'Tu sesión terminó. Vuelve a ingresar.';
    state = const AsyncData(null);
  }

  Future<void> _start(Session session) async {
    await ref.read(tokenStoreProvider).save(accessToken: session.accessToken, refreshToken: session.refreshToken);
    endedReason = null;
    state = AsyncData(session.user);
  }
}

final sessionControllerProvider = AsyncNotifierProvider<SessionController, AuthUser?>(SessionController.new);
