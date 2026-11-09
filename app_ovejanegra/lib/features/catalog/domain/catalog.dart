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

/// Una categoría de la cartilla con sus productos activos (incluidos los agotados).
class MenuSection {
  const MenuSection({required this.id, required this.name, required this.products});

  final int id;
  final String name;
  final List<Product> products;

  factory MenuSection.fromJson(Map<String, dynamic> json) => MenuSection(
        id: json['id'] as int,
        name: json['name'] as String,
        products: [for (final p in json['products'] as List) Product.fromJson(p as Map<String, dynamic>)],
      );
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
