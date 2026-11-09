import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ovejanegra/core/storage/token_store.dart';

/// Respuesta de un handler del adaptador falso: (status, cuerpo JSON).
typedef FakeResponse = (int, Map<String, dynamic>);

/// Adaptador HTTP en memoria: cada petición se resuelve con [handler], sin red.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Future<FakeResponse> Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = await handler(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class MemoryRefreshTokenStorage implements RefreshTokenStorage {
  MemoryRefreshTokenStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

Map<String, dynamic> userJson({List<String> permissions = const ['orders.create'], String role = 'CAJERO'}) => {
      'id': 7,
      'username': 'caja1',
      'full_name': 'Caja Uno',
      'role': role,
      'permissions': permissions,
    };

Map<String, dynamic> sessionJson(String access, String refresh, {List<String> permissions = const ['orders.create']}) => {
      'data': {
        'access_token': access,
        'expires_in': 900,
        'refresh_token': refresh,
        'user': userJson(permissions: permissions),
      },
    };

Map<String, dynamic> errorJson(String code, [String message = 'Error']) => {
      'error': {'code': code, 'message': message},
    };

Map<String, dynamic> productJson(int id, String name, String price, {bool available = true}) => {
      'id': id,
      'name': name,
      'description': null,
      'price': price,
      'image_url': null,
      'thumb_url': null,
      'is_available': available,
    };

Map<String, dynamic> menuJson() => {
      'data': [
        {
          'id': 1,
          'name': 'Hamburguesas',
          'products': [productJson(10, 'Clásica', '25.50'), productJson(11, 'Bacon', '32.00', available: false)],
        },
        {
          'id': 2,
          'name': 'Bebidas',
          'products': [productJson(20, 'Limonada', '10.00')],
        },
      ],
    };

/// Pedido como lo devuelve el API (`GET /orders/{id}`).
Map<String, dynamic> orderJson({
  int id = 5,
  int number = 12,
  String status = 'PENDIENTE',
  String total = '51.00',
  String paid = '0.00',
  String paymentStatus = 'SIN_PAGAR',
  List<Map<String, dynamic>> payments = const [],
}) {
  final balance = (double.parse(total) * 100).round() - (double.parse(paid) * 100).round();
  return {
    'id': id,
    'number': number,
    'business_date': '2026-11-08',
    'channel': 'LOCAL',
    'status': status,
    'customer_name': null,
    'customer_phone': null,
    'notes': null,
    'items': [
      {'id': 1, 'product_id': 10, 'name': 'Clásica', 'unit_price': '25.50', 'quantity': 2, 'line_total': '51.00'},
    ],
    'subtotal': total,
    'discount': '0.00',
    'total': total,
    'paid': paid,
    'balance': '${balance ~/ 100}.${(balance % 100).toString().padLeft(2, '0')}',
    'payment_status': paymentStatus,
    'created_by': {'id': 7, 'full_name': 'Caja Uno'},
    'cancelled': null,
    'created_at': '2026-11-08T21:30:00-04:00',
    'updated_at': '2026-11-08T21:30:00-04:00',
    'payments': payments,
  };
}

Map<String, dynamic> paymentJson(int id, String method, String amount) => {
      'id': id,
      'order_id': 5,
      'method': method,
      'amount': amount,
      'status': 'CONFIRMADO',
      'received_by': {'id': 7, 'full_name': 'Caja Uno'},
      'created_at': '2026-11-08T21:31:00-04:00',
      'voided': null,
    };
