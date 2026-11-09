import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ovejanegra/app/app.dart';
import 'package:ovejanegra/app/router.dart';
import 'package:ovejanegra/core/network/providers.dart';

import 'fakes.dart';

/// Abre la app ya con sesión (restaurada con un refresh token guardado) contra un servidor falso.
/// [routes] responde lo que no es `/auth/refresh`; devuelve el adaptador para revisar las peticiones.
Future<FakeAdapter> pumpLoggedIn(
  WidgetTester tester, {
  required List<String> permissions,
  required Future<FakeResponse> Function(RequestOptionsLike o) routes,
  String? goTo,
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final adapter = FakeAdapter((o) async => o.path == '/auth/refresh'
      ? (200, sessionJson('a1', 'r1', permissions: permissions))
      : routes(RequestOptionsLike(o.method, o.path, o.data, o.headers)));
  final container = ProviderContainer(overrides: [
    httpAdapterProvider.overrideWithValue(adapter),
    refreshTokenStorageProvider.overrideWithValue(MemoryRefreshTokenStorage('r0')),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const OvejaNegraApp()));
  await tester.pumpAndSettle();
  if (goTo != null) {
    container.read(routerProvider).go(goTo);
    await tester.pumpAndSettle();
  }
  return adapter;
}

/// Lo que los tests necesitan de una petición.
class RequestOptionsLike {
  RequestOptionsLike(this.method, this.path, this.data, this.headers);

  final String method;
  final String path;
  final dynamic data;
  final Map<String, dynamic> headers;
}
