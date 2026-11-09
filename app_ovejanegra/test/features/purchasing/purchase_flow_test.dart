import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/app_harness.dart';
import '../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  const manager = [
    'purchases.read', 'purchases.create', 'purchases.void', 'suppliers.manage',
    'ingredients.read', 'ingredients.manage', 'inventory.read', 'inventory.adjust', 'inventory.consume',
  ];

  Future<FakeResponse> common(RequestOptionsLike o) async => switch (o.path) {
        '/suppliers' => (200, {'data': []}),
        '/ingredients' => (200, {'data': [ingredientJson(3, 'Carne molida')]}),
        '/purchases' when o.method == 'GET' => (200, {'data': []}),
        '/purchases/9' => (200, {'data': purchaseJson()}),
        _ => (404, errorJson('NOT_FOUND')),
      };

  testWidgets('compra completa: total como el backend y, si la red falla, el reintento usa la misma clave', (tester) async {
    final posts = <RequestOptionsLike>[];
    await pumpLoggedIn(tester, permissions: manager, goTo: '/purchases/new', routes: (o) async {
      if (o.method == 'POST' && o.path == '/purchases') {
        posts.add(o);
        if (posts.length == 1) {
          throw DioException.connectionError(requestOptions: RequestOptions(path: o.path), reason: 'timeout');
        }
        return (201, {'data': purchaseJson()});
      }
      return common(o);
    });

    await tester.tap(find.byKey(const Key('purchase.addLine')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker.3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('purchase.quantity.0')), '2,5');
    await tester.enterText(find.byKey(const Key('purchase.price.0')), '48,50');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('purchase.total'))).data, 'Bs 121,25');

    await tester.ensureVisible(find.byKey(const Key('purchase.save')));
    await tester.tap(find.byKey(const Key('purchase.save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay conexión'), findsOneWidget);

    await tester.tap(find.byKey(const Key('purchase.save')));
    await tester.pumpAndSettle();
    expect(posts.length, 2);
    expect(posts[0].headers['Idempotency-Key'], posts[1].headers['Idempotency-Key']);
    expect((posts[1].data as Map)['items'], [
      {'ingredient_id': 3, 'quantity': '2.500', 'unit_price': '48.50'},
    ]);
    // Abre el detalle de la compra creada.
    expect(find.text('Compra del 08/11/2026'), findsOneWidget);
  });

  testWidgets('anular una compra ya consumida muestra qué falta y sugiere un ajuste', (tester) async {
    await pumpLoggedIn(tester, permissions: manager, goTo: '/purchases/9', routes: (o) async {
      if (o.path == '/purchases/9/void') {
        return (409, {
          'error': {
            'code': 'INSUFFICIENT_STOCK',
            'message': 'El stock no alcanza para esta operación.',
            'details': {
              'ingredients': [
                {'ingredient_id': 3, 'name': 'Carne molida', 'unit': 'kg', 'stock': '0.500', 'required': '2.500'},
              ],
            },
          },
        });
      }
      return common(o);
    });
    await tester.tap(find.byKey(const Key('purchase.void')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reason.field')), 'Boleta duplicada');
    await tester.tap(find.byKey(const Key('reason.confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Carne molida: hay 0,5 kg, se necesitan 2,5 kg'), findsOneWidget);
    expect(find.textContaining('registra antes un ajuste'), findsOneWidget);
  });

  testWidgets('ajuste: "Restar" envía la cantidad negativa con su motivo', (tester) async {
    Map? sent;
    await pumpLoggedIn(tester, permissions: manager, goTo: '/inventory/3', routes: (o) async {
      if (o.path == '/ingredients/3') {
        return (200, {'data': ingredientJson(3, 'Carne molida')});
      }
      if (o.path == '/inventory/movements') {
        return (200, {'data': []});
      }
      if (o.path == '/inventory/adjustments') {
        sent = o.data as Map;
        return (201, {'data': {}});
      }
      return common(o);
    });
    expect(find.text('Stock bajo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ingredient.adjust')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('adjust.quantity')), '0,25');
    await tester.enterText(find.byKey(const Key('adjust.reason')), 'Merma');
    await tester.tap(find.byKey(const Key('adjust.confirm')));
    await tester.pumpAndSettle();
    expect(sent, {'ingredient_id': 3, 'quantity': '-0.250', 'reason': 'Merma'});

    // Desde el detalle, "volver" lleva a la lista de insumos.
    await tester.tap(find.byKey(const Key('shell.back')));
    await tester.pumpAndSettle();
    expect(find.text('Solo stock bajo'), findsOneWidget);
  });

  testWidgets('sin suppliers.manage la sección Compras no muestra la pestaña de proveedores', (tester) async {
    await pumpLoggedIn(tester, permissions: ['purchases.read'], goTo: '/purchases', routes: common);
    expect(find.text('Proveedores'), findsNothing);
    expect(find.byKey(const Key('purchases.new')), findsNothing, reason: 'sin purchases.create');
    expect(find.text('Sin compras en los últimos 30 días.'), findsOneWidget);
  });
}
