import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ovejanegra/app/app.dart';
import 'package:ovejanegra/core/network/providers.dart';

import '../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late MemoryRefreshTokenStorage storage;
  late FakeAdapter adapter;

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(400, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        refreshTokenStorageProvider.overrideWithValue(storage),
        publicDioProvider.overrideWith((ref) => Dio(BaseOptions(baseUrl: 'http://api.test/v1'))..httpClientAdapter = adapter),
      ],
      child: const OvejaNegraApp(),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    storage = MemoryRefreshTokenStorage();
    adapter = FakeAdapter((o) async {
      if (o.path == '/auth/login') {
        final body = o.data as Map;
        return body['password'] == 'secreta123'
            ? (200, sessionJson('a1', 'r1', permissions: ['orders.create', 'orders.read', 'catalog.read']))
            : (401, errorJson('INVALID_CREDENTIALS', 'Usuario o contraseña incorrectos.'));
      }
      if (o.path == '/auth/logout') {
        return (200, {'data': null});
      }
      return (404, errorJson('NOT_FOUND'));
    });
  });

  testWidgets('sin sesión guardada muestra el login y valida campos vacíos', (tester) async {
    await pumpApp(tester);
    expect(find.text('Ingresar'), findsWidgets);
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pump();
    expect(find.text('Ingresa tu usuario o celular.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('credenciales incorrectas muestran el mensaje del API', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('login.identifier')), 'caja1');
    await tester.enterText(find.byKey(const Key('login.password')), 'mala-clave');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();
    expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
    expect(storage.value, isNull);
  });

  testWidgets('login correcto guarda el refresh token, abre su inicio y el menú según permisos', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('login.identifier')), ' caja1 ');
    await tester.enterText(find.byKey(const Key('login.password')), 'secreta123');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();

    expect((adapter.requests.last.data as Map)['identifier'], 'caja1');
    expect(storage.value, 'r1');
    expect(find.text('Disponible en la parte 8b de la Fase 8.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Pedidos'), findsOneWidget);
    expect(find.text('Cartilla'), findsOneWidget);
    expect(find.text('Usuarios y permisos'), findsNothing);
    expect(find.text('Compras'), findsNothing);

    await tester.tap(find.text('Mi cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account.logout')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login.submit')), findsOneWidget);
    expect(storage.value, isNull);
  });

  testWidgets('en tablet el menú queda fijo a la izquierda', (tester) async {
    storage.value = 'r0';
    adapter = FakeAdapter((o) async => o.path == '/auth/refresh'
        ? (200, sessionJson('a1', 'r1', permissions: ['dashboard.read', 'reports.read']))
        : (404, errorJson('NOT_FOUND')));
    await pumpApp(tester, size: const Size(1280, 800));
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.text('Reportes'), findsOneWidget);
    expect(find.text('Disponible en la parte 8d de la Fase 8.'), findsOneWidget);
    expect(storage.value, 'r1', reason: 'restaurar la sesión rota el refresh token');
  });
}
