import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/money.dart';
import '../domain/catalog.dart';

class CatalogApi {
  CatalogApi(this._dio);

  final Dio _dio;

  Future<List<MenuSection>> menu() => apiCall(
        () => _dio.get<dynamic>('/menu'),
        (data) => [for (final s in data as List) MenuSection.fromJson(s as Map<String, dynamic>)],
      );

  Future<List<Category>> categories() => apiCall(
        () => _dio.get<dynamic>('/categories'),
        (data) => [for (final c in data as List) Category.fromJson(c as Map<String, dynamic>)],
      );

  Future<Category> createCategory(String name, int sortOrder) => apiCall(
        () => _dio.post<dynamic>('/categories', data: {'name': name, 'sort_order': sortOrder}),
        (data) => Category.fromJson(data as Map<String, dynamic>),
      );

  Future<Category> updateCategory(int id, Map<String, dynamic> fields) => apiCall(
        () => _dio.patch<dynamic>('/categories/$id', data: fields),
        (data) => Category.fromJson(data as Map<String, dynamic>),
      );

  /// Hasta 100 productos (el máximo por página del API); suficiente para la cartilla de un local.
  Future<List<Product>> products({String? query, int? categoryId}) => apiCall(
        () => _dio.get<dynamic>('/products', queryParameters: {
          'per_page': 100,
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
          'category_id': ?categoryId,
        }),
        (data) => [for (final p in data as List) Product.fromJson(p as Map<String, dynamic>)],
      );

  Future<Product> product(int id) => apiCall(
        () => _dio.get<dynamic>('/products/$id'),
        (data) => Product.fromJson(data as Map<String, dynamic>),
      );

  Future<Product> createProduct({required int categoryId, required String name, String? description, required int priceCents}) =>
      apiCall(
        () => _dio.post<dynamic>('/products', data: {
          'category_id': categoryId,
          'name': name,
          'description': description,
          'price': Money.toApi(priceCents),
        }),
        (data) => Product.fromJson(data as Map<String, dynamic>),
      );

  Future<Product> updateProduct(int id, Map<String, dynamic> fields) => apiCall(
        () => _dio.patch<dynamic>('/products/$id', data: fields),
        (data) => Product.fromJson(data as Map<String, dynamic>),
      );

  Future<Product> changePrice(int id, int priceCents) => apiCall(
        () => _dio.patch<dynamic>('/products/$id/price', data: {'price': Money.toApi(priceCents)}),
        (data) => Product.fromJson(data as Map<String, dynamic>),
      );

  Future<Product> setActive(int id, bool active) => apiCall(
        () => _dio.patch<dynamic>('/products/$id/status', data: {'is_active': active}),
        (data) => Product.fromJson(data as Map<String, dynamic>),
      );

  Future<Product> setAvailability(int id, bool available) => apiCall(
        () => _dio.patch<dynamic>('/products/$id/availability', data: {'is_available': available}),
        (data) => Product.fromJson(data as Map<String, dynamic>),
      );

  Future<Product> uploadImage(int id, String filePath) => apiCall(
        () async => _dio.post<dynamic>('/products/$id/image',
            data: FormData.fromMap({'image': await MultipartFile.fromFile(filePath)})),
        (data) => Product.fromJson(data as Map<String, dynamic>),
      );

  Future<List<PriceChange>> priceHistory(int id) => apiCall(
        () => _dio.get<dynamic>('/products/$id/price-history'),
        (data) => [for (final h in data as List) PriceChange.fromJson(h as Map<String, dynamic>)],
      );
}
