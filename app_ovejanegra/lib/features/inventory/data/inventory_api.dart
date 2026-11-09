import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/quantity.dart';
import '../domain/inventory.dart';

class InventoryApi {
  InventoryApi(this._dio);

  final Dio _dio;

  Future<List<Unit>> units() => apiCall(
        () => _dio.get<dynamic>('/units'),
        (data) => [for (final u in data as List) Unit.fromJson(u as Map<String, dynamic>)],
      );

  Future<List<IngredientCategory>> categories() => apiCall(
        () => _dio.get<dynamic>('/ingredient-categories'),
        (data) => [for (final c in data as List) IngredientCategory.fromJson(c as Map<String, dynamic>)],
      );

  Future<IngredientCategory> createCategory(String name) => apiCall(
        () => _dio.post<dynamic>('/ingredient-categories', data: {'name': name}),
        (data) => IngredientCategory.fromJson(data as Map<String, dynamic>),
      );

  /// Hasta 100 insumos (el máximo por página del API).
  Future<List<Ingredient>> ingredients({String? query, bool lowStockOnly = false, bool? active}) => apiCall(
        () => _dio.get<dynamic>('/ingredients', queryParameters: {
          'per_page': 100,
          if (query != null && query.isNotEmpty) 'q': query,
          if (lowStockOnly) 'low_stock': 'true',
          if (active != null) 'active': '$active',
        }),
        (data) => [for (final i in data as List) Ingredient.fromJson(i as Map<String, dynamic>)],
      );

  Future<Ingredient> ingredient(int id) => apiCall(
        () => _dio.get<dynamic>('/ingredients/$id'),
        (data) => Ingredient.fromJson(data as Map<String, dynamic>),
      );

  Future<Ingredient> createIngredient(Map<String, dynamic> fields) => apiCall(
        () => _dio.post<dynamic>('/ingredients', data: fields),
        (data) => Ingredient.fromJson(data as Map<String, dynamic>),
      );

  Future<Ingredient> updateIngredient(int id, Map<String, dynamic> fields) => apiCall(
        () => _dio.patch<dynamic>('/ingredients/$id', data: fields),
        (data) => Ingredient.fromJson(data as Map<String, dynamic>),
      );

  Future<Ingredient> setActive(int id, bool active) => apiCall(
        () => _dio.patch<dynamic>('/ingredients/$id/status', data: {'is_active': active}),
        (data) => Ingredient.fromJson(data as Map<String, dynamic>),
      );

  /// Kardex: los más recientes primero; por defecto el API cubre los últimos 30 días.
  Future<List<Movement>> movements({int? ingredientId, MovementType? type, String? from, String? to}) => apiCall(
        () => _dio.get<dynamic>('/inventory/movements', queryParameters: {
          'per_page': 100,
          'ingredient_id': ?ingredientId,
          'type': ?type?.api,
          'from': ?from,
          'to': ?to,
        }),
        (data) => [for (final m in data as List) Movement.fromJson(m as Map<String, dynamic>)],
      );

  Future<void> adjust(int ingredientId, int quantityMilli, String reason) => apiCall(
        () => _dio.post<dynamic>('/inventory/adjustments',
            data: {'ingredient_id': ingredientId, 'quantity': Quantity.toApi(quantityMilli), 'reason': reason}),
        (_) {},
      );

  Future<void> consume(Map<int, int> quantities, String reason) => apiCall(
        () => _dio.post<dynamic>('/inventory/consumptions', data: {
          'reason': reason,
          'items': [
            for (final e in quantities.entries) {'ingredient_id': e.key, 'quantity': Quantity.toApi(e.value)},
          ],
        }),
        (_) {},
      );
}
