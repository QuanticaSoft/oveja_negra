import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/money.dart';
import '../domain/order.dart';

class OrdersQuery {
  const OrdersQuery({this.date, this.statuses = const {}, this.channel});

  /// Día operativo (YYYY-MM-DD); null = hoy según el servidor.
  final String? date;
  final Set<OrderStatus> statuses;
  final Channel? channel;

  @override
  bool operator ==(Object other) =>
      other is OrdersQuery && other.date == date && other.channel == channel && other.statuses.length == statuses.length &&
      other.statuses.containsAll(statuses);

  @override
  int get hashCode => Object.hash(date, channel, Object.hashAllUnordered(statuses));
}

class OrdersApi {
  OrdersApi(this._dio);

  static const _idempotencyHeader = 'Idempotency-Key';

  final Dio _dio;

  /// [key] se genera una vez por operación y se repite en los reintentos (no duplica el pedido).
  Future<Order> create(Map<String, dynamic> body, String key) => apiCall(
        () => _dio.post<dynamic>('/orders', data: body, options: Options(headers: {_idempotencyHeader: key})),
        (data) => Order.fromJson(data as Map<String, dynamic>),
      );

  /// Los pedidos más antiguos primero, como en la cocina; hasta 100.
  Future<List<Order>> list(OrdersQuery query) => apiCall(
        () => _dio.get<dynamic>('/orders', queryParameters: {
          'sort': 'asc',
          'per_page': 100,
          if (query.date != null) ...{'from': query.date, 'to': query.date},
          if (query.statuses.isNotEmpty) 'status': query.statuses.map((s) => s.api).join(','),
          'channel': ?query.channel?.api,
        }),
        (data) => [for (final o in data as List) Order.fromJson(o as Map<String, dynamic>)],
      );

  Future<Order> get(int id) => apiCall(
        () => _dio.get<dynamic>('/orders/$id'),
        (data) => Order.fromJson(data as Map<String, dynamic>),
      );

  Future<Order> replaceItems(int id, List<Map<String, dynamic>> items, int discountCents) => apiCall(
        () => _dio.patch<dynamic>('/orders/$id/items', data: {'items': items, 'discount': Money.toApi(discountCents)}),
        (data) => Order.fromJson(data as Map<String, dynamic>),
      );

  Future<Order> changeStatus(int id, OrderStatus status) => apiCall(
        () => _dio.patch<dynamic>('/orders/$id/status', data: {'status': status.api}),
        (data) => Order.fromJson(data as Map<String, dynamic>),
      );

  Future<Order> cancel(int id, String reason) => apiCall(
        () => _dio.post<dynamic>('/orders/$id/cancel', data: {'reason': reason}),
        (data) => Order.fromJson(data as Map<String, dynamic>),
      );

  Future<void> addPayment(int orderId, PaymentMethod method, int cents, String key) => apiCall(
        () => _dio.post<dynamic>('/orders/$orderId/payments',
            data: {'method': method.api, 'amount': Money.toApi(cents)},
            options: Options(headers: {_idempotencyHeader: key})),
        (_) {},
      );

  Future<void> voidPayment(int paymentId, String reason) => apiCall(
        () => _dio.post<dynamic>('/payments/$paymentId/void', data: {'reason': reason}),
        (_) {},
      );
}
