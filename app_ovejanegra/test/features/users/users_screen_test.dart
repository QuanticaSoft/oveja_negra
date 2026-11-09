import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/app_harness.dart';
import '../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  const admin = ['users.manage', 'roles.manage'];

  Map<String, dynamic> user(int id, String name, String role) => {
        'id': id, 'username': name.toLowerCase(), 'full_name': name, 'phone': null, 'role': role,
        'is_active': true, 'last_login_at': null, 'created_at': '2026-11-08T10:00:00-04:00', 'updated_at': '2026-11-08T10:00:00-04:00',
      };

  Future<FakeResponse> server(RequestOptionsLike o, {List<Map>? puts}) async {
    switch (o.path) {
      case '/users':
        return (200, {'data': [user(2, 'Otro', 'ADMIN')]});
      case '/users/2/status':
        return (409, errorJson('LAST_ADMIN', 'Debe quedar al menos un ADMIN activo.'));
      case '/roles':
        return (200, {'data': [
          {'id': 1, 'code': 'ADMIN', 'name': 'Administrador', 'permissions': ['users.manage', 'roles.manage', 'orders.create']},
          {'id': 2, 'code': 'CAJERO', 'name': 'Cajero', 'permissions': ['orders.create']},
        ]});
      case '/permissions':
        return (200, {'data': [
          {'code': 'orders.create', 'description': 'Registrar pedidos'},
          {'code': 'orders.cancel', 'description': 'Cancelar pedidos'},
          {'code': 'roles.manage', 'description': 'Administrar roles y permisos'},
          {'code': 'users.manage', 'description': 'Administrar usuarios'},
        ]});
      case '/roles/2/permissions':
        puts?.add(o.data as Map);
        return (200, {'data': {}});
    }
    return (404, errorJson('NOT_FOUND'));
  }

  testWidgets('desactivar al último ADMIN muestra el motivo claro', (tester) async {
    await pumpLoggedIn(tester, permissions: admin, goTo: '/users', routes: server);
    await tester.tap(find.byKey(const Key('user.menu.2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('user.status.2')));
    await tester.pumpAndSettle();
    expect(find.text('Debe quedar al menos un ADMIN activo.'), findsOneWidget);
  });

  testWidgets('matriz: el ADMIN no puede perder la administración; guardar envía el conjunto completo', (tester) async {
    final puts = <Map>[];
    await pumpLoggedIn(tester, permissions: admin, goTo: '/users', size: const Size(1280, 1000), routes: (o) => server(o, puts: puts));
    await tester.tap(find.text('Permisos por rol'));
    await tester.pumpAndSettle();

    final locked = tester.widget<CheckboxListTile>(find.byKey(const Key('perm.users.manage')));
    expect(locked.onChanged, isNull, reason: 'ADMIN conserva users.manage');

    await tester.tap(find.byKey(const Key('roles.CAJERO')));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('perm.users.manage'))).onChanged, isNotNull);
    await tester.tap(find.byKey(const Key('perm.orders.cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('roles.save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('roles.confirm')));
    await tester.pumpAndSettle();
    expect(puts.single, {'permissions': ['orders.cancel', 'orders.create']});
  });

  testWidgets('sin roles.manage no aparece la pestaña de permisos', (tester) async {
    await pumpLoggedIn(tester, permissions: ['users.manage'], goTo: '/users', routes: server);
    expect(find.text('Permisos por rol'), findsNothing);
    expect(find.text('Otro'), findsOneWidget);
  });
}
