import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../data/catalog_api.dart';
import '../domain/catalog.dart';

final catalogApiProvider = Provider<CatalogApi>((ref) => CatalogApi(ref.watch(apiDioProvider)));

final menuProvider = FutureProvider.autoDispose<List<MenuSection>>((ref) => ref.watch(catalogApiProvider).menu());

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) => ref.watch(catalogApiProvider).categories());

final productsProvider = FutureProvider.autoDispose.family<List<Product>, String>(
  (ref, query) => ref.watch(catalogApiProvider).products(query: query),
);

final productProvider = FutureProvider.autoDispose.family<Product, int>((ref, id) => ref.watch(catalogApiProvider).product(id));

final priceHistoryProvider =
    FutureProvider.autoDispose.family<List<PriceChange>, int>((ref, id) => ref.watch(catalogApiProvider).priceHistory(id));

/// Después de cambiar algo del catálogo, todo lo que lo muestra se vuelve a pedir.
void refreshCatalog(WidgetRef ref) {
  ref
    ..invalidate(menuProvider)
    ..invalidate(categoriesProvider)
    ..invalidate(productsProvider)
    ..invalidate(productProvider)
    ..invalidate(priceHistoryProvider);
}
