import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/app_harness.dart';
import '../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('Personalizar: extra por desplegable con cantidad, bebida aparte y nota', (tester) async {
    Map<String, dynamic>? sent;
    await pumpLoggedIn(tester, permissions: ['orders.create', 'catalog.read'], routes: (o) async {
      if (o.path == '/menu') {
        return (200, menuJson(extras: true));
      }
      if (o.method == 'POST' && o.path == '/orders') {
        sent = Map<String, dynamic>.from(o.data as Map);
        return (201, {'data': orderJson(number: 7)});
      }
      return (404, errorJson('NOT_FOUND'));
    });

    await tester.tap(find.byKey(const Key('product.10')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customize.addExtra')));
    await tester.pumpAndSettle();
    // Se elige el primer extra disponible (Huevo); Tocino está agotado, así que no hay otro para sumar.
    expect(find.text('Huevo +Bs 4'), findsOneWidget);
    expect(find.byKey(const Key('customize.addExtra')), findsNothing);
    await tester.tap(find.byKey(const Key('customize.extra.0.plus')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('customize.drink')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limonada · Bs 10').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('customize.notes')), 'sin cebolla');
    await tester.pump();
    // 25,50 + 2 × 4 = 33,50 más la limonada (10) = 43,50
    expect(find.text('Agregar · Bs 43,50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('customize.add')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sale.openCart')));
    await tester.pumpAndSettle();
    expect(find.text('+ Huevo ×2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sale.saveUnpaid')));
    await tester.pumpAndSettle();

    expect(sent!['items'], [
      {'product_id': 10, 'quantity': 1, 'notes': 'sin cebolla', 'extras': [{'extra_id': 1, 'quantity': 2}]},
      {'product_id': 20, 'quantity': 1},
    ]);
    expect(find.text('Pedido #7'), findsOneWidget);
  });

  testWidgets('quitar un extra elegido y no elegir bebida deja solo el producto', (tester) async {
    await pumpLoggedIn(tester, permissions: ['orders.create', 'catalog.read'],
        routes: (o) async => o.path == '/menu' ? (200, menuJson(extras: true)) : (404, errorJson('NOT_FOUND')));
    await tester.tap(find.byKey(const Key('product.10')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customize.addExtra')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customize.extra.0.remove')));
    await tester.pumpAndSettle();
    expect(find.text('Agregar · Bs 25,50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('customize.add')));
    await tester.pumpAndSettle();
    expect(find.text('Ver pedido (1) · Bs 25,50'), findsOneWidget);
  });

  testWidgets('un producto sin extras en su categoría se agrega directo, sin hoja', (tester) async {
    await pumpLoggedIn(tester, permissions: ['orders.create', 'catalog.read'],
        routes: (o) async => o.path == '/menu' ? (200, menuJson(extras: true)) : (404, errorJson('NOT_FOUND')));
    await tester.tap(find.byKey(const Key('product.20')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customize.add')), findsNothing);
    expect(find.text('Ver pedido (1) · Bs 10'), findsOneWidget);
  });
}
