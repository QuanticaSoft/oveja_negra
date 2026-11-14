import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/app_harness.dart';
import '../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('Personalizar: extra agotado deshabilitado, precio en vivo y envío con extras y nota', (tester) async {
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
    expect(find.text('Agotado'), findsOneWidget, reason: 'Tocino sin stock');
    expect(find.byKey(const Key('customize.extra.2.plus')), findsNothing);

    await tester.tap(find.byKey(const Key('customize.extra.1.plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('customize.extra.1.plus')));
    await tester.enterText(find.byKey(const Key('customize.notes')), 'sin cebolla');
    await tester.pump();
    // 25,50 + 2 × 4 = 33,50
    expect(find.text('Agregar · Bs 33,50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('customize.add')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sale.openCart')));
    await tester.pumpAndSettle();
    expect(find.text('+ Huevo ×2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sale.saveUnpaid')));
    await tester.pumpAndSettle();

    expect(sent!['items'], [
      {'product_id': 10, 'quantity': 1, 'notes': 'sin cebolla', 'extras': [{'extra_id': 1, 'quantity': 2}]},
    ]);
    expect(find.text('Pedido #7'), findsOneWidget);
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
