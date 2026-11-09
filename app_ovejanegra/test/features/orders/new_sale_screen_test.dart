import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/app_harness.dart';
import '../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  const cashier = ['orders.create', 'orders.read', 'orders.discount', 'payments.create', 'catalog.read', 'products.availability'];

  testWidgets('venta completa en teléfono: agrega, cobra en efectivo con vuelto y muestra el número', (tester) async {
    Map<String, dynamic>? sent;
    String? key;
    final adapter = await pumpLoggedIn(tester, permissions: cashier, routes: (o) async {
      if (o.path == '/menu') {
        return (200, menuJson());
      }
      if (o.method == 'POST' && o.path == '/orders') {
        sent = Map<String, dynamic>.from(o.data as Map);
        key = o.headers['Idempotency-Key'] as String?;
        return (201, {'data': orderJson(number: 12, paid: '51.00', paymentStatus: 'PAGADO')});
      }
      return (404, errorJson('NOT_FOUND'));
    });

    expect(find.text('Clásica'), findsOneWidget);
    expect(find.text('AGOTADO'), findsOneWidget);
    // Un producto agotado no se agrega.
    await tester.tap(find.byKey(const Key('product.11')));
    await tester.pump();
    expect(find.byKey(const Key('sale.openCart')), findsNothing);

    await tester.tap(find.byKey(const Key('product.10')));
    await tester.tap(find.byKey(const Key('product.10')));
    await tester.pump();
    expect(find.text('Ver pedido (2) · Bs 51'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sale.openCart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sale.charge')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('payment.received.0')), '100');
    await tester.pump();
    expect(find.text('Vuelto: Bs 49'), findsOneWidget);
    await tester.tap(find.byKey(const Key('payment.confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Pedido #12'), findsOneWidget);
    expect(find.text('Vuelto: Bs 49'), findsOneWidget);
    expect(sent, {
      'channel': 'LOCAL',
      'items': [
        {'product_id': 10, 'quantity': 2},
      ],
      'payments': [
        {'method': 'EFECTIVO', 'amount': '51.00'},
      ],
    }, reason: 'el recibido (Bs 100) no se envía: solo el monto aplicado');
    expect(key, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(adapter.requests.where((r) => r.path == '/orders').length, 1);
  });

  testWidgets('sin payments.create solo puede guardar el pedido, sin cobrar', (tester) async {
    await pumpLoggedIn(tester,
        permissions: ['orders.create', 'catalog.read'],
        size: const Size(1280, 900),
        routes: (o) async => o.path == '/menu' ? (200, menuJson()) : (404, errorJson('NOT_FOUND')));
    await tester.tap(find.byKey(const Key('product.20')));
    await tester.pump();
    // En tablet el pedido está siempre a la vista.
    expect(find.byKey(const Key('sale.charge')), findsNothing);
    expect(find.text('Guardar pedido'), findsOneWidget);
    expect(find.byKey(const Key('sale.discount')), findsNothing, reason: 'sin orders.discount');
  });
}
