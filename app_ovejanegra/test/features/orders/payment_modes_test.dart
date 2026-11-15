import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ovejanegra/app/destinations.dart';
import 'package:ovejanegra/features/auth/domain/auth_user.dart';

import '../../support/app_harness.dart';
import '../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  const cashier = ['orders.create', 'payments.create', 'catalog.read'];

  Map<String, dynamic> settingsJson({bool qr = true}) => {
        'data': {
          'bank_name': 'Banco Unión',
          'account_holder': 'Oveja Negra',
          'account_number': null,
          'qr_url': qr ? 'http://api.test/media/qr/2026/11/abc.png' : null,
          'updated_at': '2026-11-15T10:00:00-04:00',
        },
      };

  /// Agrega 2 Clásicas (Bs 51) y abre la hoja de cobro.
  Future<void> openCharge(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('product.10')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('product.10')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sale.openCart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sale.charge')));
    await tester.pumpAndSettle();
  }

  testWidgets('Mixto: el QR cubre el resto, vuelto del efectivo, pantalla QR con el monto y 2 pagos', (tester) async {
    Map<String, dynamic>? sent;
    await pumpLoggedIn(tester, permissions: cashier, routes: (o) async {
      if (o.path == '/menu') {
        return (200, menuJson());
      }
      if (o.path == '/payment-settings') {
        return (200, settingsJson());
      }
      if (o.method == 'POST' && o.path == '/orders') {
        sent = Map<String, dynamic>.from(o.data as Map);
        return (201, {'data': orderJson(number: 8, paid: '51.00', paymentStatus: 'PAGADO')});
      }
      return (404, errorJson('NOT_FOUND'));
    });
    await openCharge(tester);

    await tester.tap(find.text('Mixto'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('payment.confirm'))).onPressed, isNull,
        reason: 'sin efectivo no es mixto');
    await tester.enterText(find.byKey(const Key('payment.cash')), '30');
    await tester.enterText(find.byKey(const Key('payment.received.0')), '50');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('payment.qrRemainder'))).data, 'Bs 21');
    expect(find.text('Vuelto: Bs 20'), findsOneWidget);

    await tester.tap(find.byKey(const Key('payment.showQr')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('qr.amount'))).data, 'Bs 21');
    expect(find.byKey(const Key('qr.image')), findsOneWidget);
    expect(find.text('Banco Unión · Oveja Negra'), findsOneWidget);
    await tester.tap(find.text('Volver al cobro'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('payment.confirm')));
    await tester.pumpAndSettle();
    expect(sent!['payments'], [
      {'method': 'EFECTIVO', 'amount': '30.00'},
      {'method': 'QR', 'amount': '21.00'},
    ]);
    expect(find.text('Pedido #8'), findsOneWidget);
  });

  testWidgets('Solo QR: muestra el total; sin QR cargado avisa y deja registrar el pago igual', (tester) async {
    Map<String, dynamic>? sent;
    await pumpLoggedIn(tester, permissions: cashier, routes: (o) async {
      if (o.path == '/menu') {
        return (200, menuJson());
      }
      if (o.path == '/payment-settings') {
        return (200, settingsJson(qr: false));
      }
      if (o.method == 'POST' && o.path == '/orders') {
        sent = Map<String, dynamic>.from(o.data as Map);
        return (201, {'data': orderJson(number: 9, paid: '51.00', paymentStatus: 'PAGADO')});
      }
      return (404, errorJson('NOT_FOUND'));
    });
    await openCharge(tester);

    await tester.tap(find.text('QR'));
    await tester.pumpAndSettle();
    expect(find.text('Mostrar QR · Bs 51'), findsOneWidget);
    await tester.tap(find.byKey(const Key('payment.showQr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qr.missing')), findsOneWidget);
    await tester.tap(find.text('Volver al cobro'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payment.confirm')));
    await tester.pumpAndSettle();
    expect(sent!['payments'], [
      {'method': 'QR', 'amount': '51.00'},
    ]);
  });

  test('la configuración de cobro solo aparece con settings.manage', () {
    AuthUser user(List<String> p) => AuthUser(id: 1, username: 'u', fullName: 'U', role: 'X', permissions: {...p});
    expect(destinationsFor(user(['settings.manage'])).map((d) => d.path), ['/settings']);
    expect(destinationsFor(user(['orders.create', 'payments.create'])).map((d) => d.path), isNot(contains('/settings')));
  });
}
