import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/app_harness.dart';
import '../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  const manager = ['dashboard.read', 'reports.read', 'finance.read', 'expenses.read', 'expenses.create', 'expenses.void', 'ingredients.read'];

  testWidgets('dashboard: importes del servidor, resultado negativo en rojo, top y stock bajo', (tester) async {
    await pumpLoggedIn(tester, permissions: manager, size: const Size(1280, 1000), routes: (o) async {
      if (o.path == '/dashboard') {
        return (200, {'data': dashboardJson()});
      }
      return (404, errorJson('NOT_FOUND'));
    });

    expect(find.text('Bs 51'), findsOneWidget);
    expect(find.text('Efectivo Bs 30 · QR Bs 21'), findsOneWidget);
    final result = tester.widget<Text>(find.descendant(of: find.byKey(const Key('kpi.result')), matching: find.text('Bs -64')));
    expect(result.style?.color, Theme.of(tester.element(find.byKey(const Key('kpi.result')))).colorScheme.error);
    expect(find.text('3 u · Bs 76,50'), findsOneWidget);
    expect(find.text('Carne molida'), findsOneWidget);
    expect(find.text('1 cancelados'), findsOneWidget);
  });

  testWidgets('gasto: si la red falla, el reintento usa la misma clave', (tester) async {
    final posts = <RequestOptionsLike>[];
    await pumpLoggedIn(tester, permissions: manager, goTo: '/expenses/new', routes: (o) async {
      if (o.path == '/expense-categories') {
        return (200, {'data': [
          {'id': 4, 'name': 'Gas', 'is_active': true},
        ]});
      }
      if (o.path == '/expenses' && o.method == 'POST') {
        posts.add(o);
        if (posts.length == 1) {
          throw DioException.connectionError(requestOptions: RequestOptions(path: o.path), reason: 'timeout');
        }
        return (201, {'data': {
          'id': 1, 'expense_date': '2026-11-08', 'category': {'id': 4, 'name': 'Gas'}, 'description': 'Garrafa',
          'amount': '22.50', 'payment_method': 'EFECTIVO', 'status': 'CONFIRMADO', 'created_by': {'id': 8, 'full_name': 'Enc'},
          'voided': null,
        }});
      }
      if (o.path == '/expenses') {
        return (200, {'data': []});
      }
      return (404, errorJson('NOT_FOUND'));
    });

    await tester.tap(find.byKey(const Key('expense.category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gas').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expense.description')), 'Garrafa');
    await tester.enterText(find.byKey(const Key('expense.amount')), '22,50');
    await tester.tap(find.byKey(const Key('expense.save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay conexión'), findsOneWidget);
    await tester.tap(find.byKey(const Key('expense.save')));
    await tester.pumpAndSettle();

    expect(posts.length, 2);
    expect(posts[0].headers['Idempotency-Key'], posts[1].headers['Idempotency-Key']);
    expect((posts[1].data as Map)['amount'], '22.50');
    expect(find.text('Sin gastos en los últimos 30 días.'), findsOneWidget, reason: 'vuelve al listado');
  });

  testWidgets('flujo financiero: muestra cada día (también los vacíos) con su acumulado', (tester) async {
    await pumpLoggedIn(tester, permissions: manager, goTo: '/reports/flow', routes: (o) async {
      if (o.path == '/reports/finance/movements') {
        return (200, {'data': {'from': '2026-11-02', 'to': '2026-11-03', 'days': [
          {'date': '2026-11-02', 'income': '0.00', 'outcome': '150.00', 'net': '-150.00', 'cumulative': '-150.00'},
          {'date': '2026-11-03', 'income': '0.00', 'outcome': '0.00', 'net': '0.00', 'cumulative': '-150.00'},
        ]}});
      }
      return (404, errorJson('NOT_FOUND'));
    });
    expect(find.byKey(const Key('flow.2026-11-03')), findsOneWidget);
    expect(find.textContaining('Acumulado Bs -150'), findsNWidgets(2));
    expect(find.text('Bs 0'), findsOneWidget);
  });

  testWidgets('el menú de reportes muestra el libro solo con finance.read', (tester) async {
    await pumpLoggedIn(tester, permissions: ['reports.read'], goTo: '/reports', routes: (o) async => (404, errorJson('NOT_FOUND')));
    expect(find.byKey(const Key('report.sales-daily')), findsOneWidget);
    expect(find.byKey(const Key('report.ledger')), findsNothing);
  });
}
