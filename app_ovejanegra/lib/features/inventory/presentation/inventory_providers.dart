import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/quantity.dart';
import '../data/inventory_api.dart';
import '../domain/inventory.dart';

final inventoryApiProvider = Provider<InventoryApi>((ref) => InventoryApi(ref.watch(apiDioProvider)));

typedef IngredientsQuery = ({String query, bool lowStockOnly});

final ingredientsProvider = FutureProvider.autoDispose.family<List<Ingredient>, IngredientsQuery>(
  (ref, q) => ref.watch(inventoryApiProvider).ingredients(query: q.query, lowStockOnly: q.lowStockOnly),
);

final ingredientProvider =
    FutureProvider.autoDispose.family<Ingredient, int>((ref, id) => ref.watch(inventoryApiProvider).ingredient(id));

typedef MovementsQuery = ({int? ingredientId, MovementType? type});

final movementsProvider = FutureProvider.autoDispose.family<List<Movement>, MovementsQuery>(
  (ref, q) => ref.watch(inventoryApiProvider).movements(ingredientId: q.ingredientId, type: q.type),
);

final unitsProvider = FutureProvider.autoDispose<List<Unit>>((ref) => ref.watch(inventoryApiProvider).units());

final ingredientCategoriesProvider =
    FutureProvider.autoDispose<List<IngredientCategory>>((ref) => ref.watch(inventoryApiProvider).categories());

void refreshInventory(WidgetRef ref) {
  ref
    ..invalidate(ingredientsProvider)
    ..invalidate(ingredientProvider)
    ..invalidate(movementsProvider)
    ..invalidate(ingredientCategoriesProvider);
}

/// `INSUFFICIENT_STOCK` / `INGREDIENT_INACTIVE` con el detalle de cada insumo, en una frase legible.
String inventoryErrorMessage(ApiException e) {
  final ingredients = e.details['ingredients'];
  if (ingredients is! List || ingredients.isEmpty) {
    return e.message;
  }
  if (e.code == 'INSUFFICIENT_STOCK') {
    final lines = [
      for (final i in ingredients.cast<Map>())
        '${i['name']}: hay ${Quantity.format(Quantity.toMilli(i['stock'] as String), i['unit'] as String)}, '
            'se necesitan ${Quantity.format(Quantity.toMilli(i['required'] as String), i['unit'] as String)}',
    ];
    return '${e.message}\n${lines.join('\n')}';
  }
  return '${e.message} ${[for (final i in ingredients.cast<Map>()) i['name']].join(', ')}.';
}
