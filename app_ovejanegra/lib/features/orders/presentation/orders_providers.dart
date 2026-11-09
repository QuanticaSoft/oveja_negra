import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/network/providers.dart';
import '../../catalog/domain/catalog.dart';
import '../data/orders_api.dart';
import '../domain/cart.dart';
import '../domain/order.dart';

final ordersApiProvider = Provider<OrdersApi>((ref) => OrdersApi(ref.watch(apiDioProvider)));

final ordersProvider =
    FutureProvider.autoDispose.family<List<Order>, OrdersQuery>((ref, query) => ref.watch(ordersApiProvider).list(query));

final orderProvider = FutureProvider.autoDispose.family<Order, int>((ref, id) => ref.watch(ordersApiProvider).get(id));

/// Carrito de "Nueva venta". Vive mientras la app está abierta: cambiar de sección no lo pierde.
class CartController extends Notifier<Cart> {
  final _operation = IdempotentOperation();

  /// Productos que el servidor rechazó por agotados en el último intento.
  Set<int> unavailable = {};

  @override
  Cart build() => const Cart();

  void add(Product product) => state = state.add(product);
  void setQuantity(int productId, int quantity) => state = state.setQuantity(productId, quantity);
  void setChannel(Channel channel) => state = state.withChannel(channel);
  void setDiscount(int cents) => state = state.withDiscount(cents);
  void setCustomer({String? name, String? phone}) => state = state.withCustomer(name: name, phone: phone);
  void setNotes(String notes) => state = state.withNotes(notes);
  void clear() {
    unavailable = {};
    state = const Cart();
  }

  /// Registra el pedido (con sus pagos, si los hay). Un reintento con el mismo contenido usa la
  /// misma Idempotency-Key: si el primer intento sí llegó al servidor, no se crea otro pedido.
  Future<Order> submit(List<PaymentDraft> payments) async {
    final body = state.toApi(payments);
    try {
      final order = await ref.read(ordersApiProvider).create(body, _operation.keyFor(body));
      _operation.done();
      unavailable = {};
      state = const Cart();
      return order;
    } on ApiException catch (e) {
      if (e.code == 'PRODUCT_UNAVAILABLE') {
        unavailable = {for (final p in e.details['products'] as List? ?? const []) (p as Map)['id'] as int};
        ref.notifyListeners();
      }
      rethrow;
    }
  }
}

final cartControllerProvider = NotifierProvider<CartController, Cart>(CartController.new);
