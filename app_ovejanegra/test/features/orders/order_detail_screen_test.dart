import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/app_harness.dart';
import '../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<FakeResponse> server(RequestOptionsLike o) async {
    if (o.path == '/orders/5') {
      return (200, {
        'data': orderJson(paid: '20.00', paymentStatus: 'PARCIAL', status: 'LISTO', payments: [paymentJson(1, 'QR', '20.00')]),
      });
    }
    if (o.path == '/orders') {
      return (200, {'data': []});
    }
    return (404, errorJson('NOT_FOUND'));
  }

  testWidgets('CAJERO: cobra y cambia estado, pero no cancela ni anula pagos; sin saldo 0 no se entrega', (tester) async {
    await pumpLoggedIn(tester,
        permissions: ['orders.create', 'orders.read', 'orders.update_status', 'payments.create'], goTo: '/orders/5', routes: server);

    expect(find.text('#12'), findsOneWidget);
    expect(find.text('Cobrar Bs 31'), findsOneWidget);
    final deliver = tester.widget<FilledButton>(find.byKey(const Key('order.status.ENTREGADO')));
    expect(deliver.onPressed, isNull);
    expect(find.text('Para entregarlo, primero cobra el saldo.'), findsOneWidget);
    expect(find.byKey(const Key('order.cancel')), findsNothing);
    expect(find.byKey(const Key('payment.void.1')), findsNothing);
    expect(find.byKey(const Key('order.editItems')), findsNothing, reason: 'tiene pagos y no está PENDIENTE');
  });

  testWidgets('ADMIN: puede cancelar (con motivo) y anular pagos', (tester) async {
    String? cancelReason;
    await pumpLoggedIn(tester,
        permissions: ['orders.read', 'orders.update_status', 'orders.cancel', 'payments.create', 'payments.void'],
        goTo: '/orders/5', routes: (o) async {
      if (o.path == '/orders/5/cancel') {
        cancelReason = (o.data as Map)['reason'] as String;
        return (200, {'data': orderJson(status: 'CANCELADO')});
      }
      return server(o);
    });

    expect(find.byKey(const Key('payment.void.1')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('order.cancel')));
    await tester.tap(find.byKey(const Key('order.cancel')));
    await tester.pumpAndSettle();
    // Sin motivo no se puede confirmar.
    await tester.tap(find.byKey(const Key('reason.confirm')));
    await tester.pump();
    expect(find.text('El motivo es obligatorio.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reason.field')), 'Cliente no vino');
    await tester.tap(find.byKey(const Key('reason.confirm')));
    await tester.pumpAndSettle();
    expect(cancelReason, 'Cliente no vino');
  });

  testWidgets('Cartilla: el interruptor de agotado solo aparece con products.availability', (tester) async {
    await pumpLoggedIn(tester,
        permissions: ['catalog.read'],
        goTo: '/menu',
        routes: (o) async => o.path == '/menu' ? (200, menuJson()) : (404, errorJson('NOT_FOUND')));
    expect(find.text('Clásica'), findsOneWidget);
    expect(find.byKey(const Key('menu.available.10')), findsNothing);
    expect(find.text('AGOTADO'), findsOneWidget);
  });
}
