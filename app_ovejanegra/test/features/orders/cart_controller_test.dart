import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ovejanegra/core/network/api_exception.dart';
import 'package:ovejanegra/core/network/providers.dart';
import 'package:ovejanegra/features/catalog/domain/catalog.dart';
import 'package:ovejanegra/features/orders/presentation/orders_providers.dart';

import '../../support/fakes.dart';

void main() {
  const burger = Product(id: 10, name: 'Clásica', priceCents: 2550, isAvailable: true);

  test('si la red falla, el reintento usa la MISMA Idempotency-Key; la siguiente venta, otra', () async {
    var calls = 0;
    final adapter = FakeAdapter((o) async {
      calls++;
      if (calls == 1) {
        // El pedido llegó al servidor pero la respuesta se perdió.
        throw DioException.connectionError(requestOptions: o, reason: 'timeout');
      }
      return (201, {'data': orderJson()});
    });
    final container = ProviderContainer.test(overrides: [
      httpAdapterProvider.overrideWithValue(adapter),
      refreshTokenStorageProvider.overrideWithValue(MemoryRefreshTokenStorage()),
    ]);
    final cart = container.read(cartControllerProvider.notifier)
      ..add(burger)
      ..add(burger);

    await expectLater(cart.submit(const []), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'red', isTrue)));
    expect(container.read(cartControllerProvider).quantityOf(10), 2, reason: 'el carrito se conserva para reintentar');

    final order = await cart.submit(const []);
    expect(order.number, 12);
    final keys = adapter.requests.map((r) => r.headers['Idempotency-Key']).toList();
    expect(keys[0], keys[1]);
    expect(container.read(cartControllerProvider).isEmpty, isTrue);

    cart
      ..add(burger)
      ..add(burger);
    await cart.submit(const []);
    expect(adapter.requests.last.headers['Idempotency-Key'], isNot(keys[0]));
  });

  test('PRODUCT_UNAVAILABLE marca los productos rechazados', () async {
    final adapter = FakeAdapter((o) async => (409, {
          'error': {
            'code': 'PRODUCT_UNAVAILABLE',
            'message': 'Hay productos agotados.',
            'details': {
              'products': [
                {'id': 10, 'name': 'Clásica'},
              ],
            },
          },
        }));
    final container = ProviderContainer.test(overrides: [
      httpAdapterProvider.overrideWithValue(adapter),
      refreshTokenStorageProvider.overrideWithValue(MemoryRefreshTokenStorage()),
    ]);
    final cart = container.read(cartControllerProvider.notifier)..add(burger);
    await expectLater(cart.submit(const []), throwsA(isA<ApiException>()));
    expect(cart.unavailable, {10});
    cart.clear();
    expect(cart.unavailable, isEmpty);
  });
}
