import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/purchasing.dart';

class PurchasingApi {
  PurchasingApi(this._dio);

  final Dio _dio;

  Future<List<Supplier>> suppliers({bool? active}) => apiCall(
        () => _dio.get<dynamic>('/suppliers', queryParameters: {if (active != null) 'active': '$active'}),
        (data) => [for (final s in data as List) Supplier.fromJson(s as Map<String, dynamic>)],
      );

  Future<Supplier> createSupplier(Map<String, dynamic> fields) => apiCall(
        () => _dio.post<dynamic>('/suppliers', data: fields),
        (data) => Supplier.fromJson(data as Map<String, dynamic>),
      );

  Future<Supplier> updateSupplier(int id, Map<String, dynamic> fields) => apiCall(
        () => _dio.patch<dynamic>('/suppliers/$id', data: fields),
        (data) => Supplier.fromJson(data as Map<String, dynamic>),
      );

  /// Por defecto, los últimos 30 días.
  Future<List<Purchase>> purchases({String? status}) => apiCall(
        () => _dio.get<dynamic>('/purchases', queryParameters: {'per_page': 100, 'status': ?status}),
        (data) => [for (final p in data as List) Purchase.fromJson(p as Map<String, dynamic>)],
      );

  Future<Purchase> purchase(int id) => apiCall(
        () => _dio.get<dynamic>('/purchases/$id'),
        (data) => Purchase.fromJson(data as Map<String, dynamic>),
      );

  /// [key] se repite en los reintentos: la compra no se duplica.
  Future<Purchase> create(Map<String, dynamic> body, String key) => apiCall(
        () => _dio.post<dynamic>('/purchases', data: body, options: Options(headers: {'Idempotency-Key': key})),
        (data) => Purchase.fromJson(data as Map<String, dynamic>),
      );

  Future<Purchase> voidPurchase(int id, String reason) => apiCall(
        () => _dio.post<dynamic>('/purchases/$id/void', data: {'reason': reason}),
        (data) => Purchase.fromJson(data as Map<String, dynamic>),
      );
}
