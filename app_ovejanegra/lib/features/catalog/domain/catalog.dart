import '../../../core/utils/money.dart';

class Category {
  const Category({required this.id, required this.name, required this.sortOrder, required this.isActive});

  final int id;
  final String name;
  final int sortOrder;
  final bool isActive;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int,
        name: json['name'] as String,
        sortOrder: json['sort_order'] as int,
        isActive: json['is_active'] as bool,
      );
}

/// Producto tal como lo devuelven `/products` y `/menu` (en la cartilla, sin categoría ni estado).
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.isAvailable,
    this.description,
    this.imageUrl,
    this.thumbUrl,
    this.categoryId,
    this.categoryName,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String? description;
  final int priceCents;
  final String? imageUrl;
  final String? thumbUrl;
  final bool isAvailable;
  final bool isActive;
  final int? categoryId;
  final String? categoryName;

  factory Product.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    return Product(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      priceCents: Money.toCents(json['price'] as String),
      imageUrl: json['image_url'] as String?,
      thumbUrl: json['thumb_url'] as String?,
      isAvailable: json['is_available'] as bool,
      isActive: json['is_active'] as bool? ?? true,
      categoryId: category?['id'] as int?,
      categoryName: category?['name'] as String?,
    );
  }
}

/// Una categoría de la cartilla con sus productos activos (incluidos los agotados) y sus extras.
class MenuSection {
  const MenuSection({required this.id, required this.name, required this.products, this.extras = const []});

  final int id;
  final String name;
  final List<Product> products;

  /// Extras que acepta la categoría (huevo, queso…), con disponibilidad ya calculada por el servidor.
  final List<MenuExtra> extras;

  factory MenuSection.fromJson(Map<String, dynamic> json) => MenuSection(
        id: json['id'] as int,
        name: json['name'] as String,
        products: [for (final p in json['products'] as List) Product.fromJson(p as Map<String, dynamic>)],
        extras: [for (final e in json['extras'] as List? ?? const []) MenuExtra.fromJson(e as Map<String, dynamic>)],
      );
}

/// Extra tal como aparece en la cartilla: disponible = activo, no agotado y con stock del insumo.
class MenuExtra {
  const MenuExtra({required this.id, required this.name, required this.priceCents, required this.isAvailable});

  final int id;
  final String name;
  final int priceCents;
  final bool isAvailable;

  factory MenuExtra.fromJson(Map<String, dynamic> json) => MenuExtra(
        id: json['id'] as int,
        name: json['name'] as String,
        priceCents: Money.toCents(json['price'] as String),
        isAvailable: json['is_available'] as bool,
      );
}

/// Extra completo, para administrarlo (`GET /v1/extras`).
class Extra {
  const Extra({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.sortOrder,
    required this.isActive,
    required this.isAvailable,
    required this.inStock,
    required this.categoryIds,
    this.ingredientId,
    this.ingredientName,
    this.ingredientUnit,
    this.ingredientQuantity,
  });

  final int id;
  final String name;
  final int priceCents;
  final int? ingredientId;
  final String? ingredientName;
  final String? ingredientUnit;

  /// Cantidad del insumo por porción, como texto NUMERIC ("0.020").
  final String? ingredientQuantity;
  final int sortOrder;
  final bool isActive;
  final bool isAvailable;
  final bool inStock;
  final List<int> categoryIds;

  factory Extra.fromJson(Map<String, dynamic> json) {
    final ingredient = json['ingredient'] as Map<String, dynamic>?;
    return Extra(
      id: json['id'] as int,
      name: json['name'] as String,
      priceCents: Money.toCents(json['price'] as String),
      ingredientId: ingredient?['id'] as int?,
      ingredientName: ingredient?['name'] as String?,
      ingredientUnit: ingredient?['unit'] as String?,
      ingredientQuantity: ingredient?['quantity'] as String?,
      sortOrder: json['sort_order'] as int,
      isActive: json['is_active'] as bool,
      isAvailable: json['is_available'] as bool,
      inStock: json['in_stock'] as bool,
      categoryIds: [...(json['category_ids'] as List? ?? const []).cast<int>()],
    );
  }
}

class PriceChange {
  const PriceChange({required this.oldCents, required this.newCents, required this.changedAt, required this.changedBy});

  final int oldCents;
  final int newCents;
  final String changedAt;
  final String changedBy;

  factory PriceChange.fromJson(Map<String, dynamic> json) => PriceChange(
        oldCents: Money.toCents(json['old_price'] as String),
        newCents: Money.toCents(json['new_price'] as String),
        changedAt: json['changed_at'] as String,
        changedBy: (json['changed_by'] as Map)['full_name'] as String,
      );
}
