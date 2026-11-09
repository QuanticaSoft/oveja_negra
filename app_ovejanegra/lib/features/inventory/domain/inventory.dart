import '../../../core/utils/money.dart';
import '../../../core/utils/quantity.dart';

class Unit {
  const Unit({required this.id, required this.code, required this.name});

  final int id;
  final String code;
  final String name;

  factory Unit.fromJson(Map<String, dynamic> json) =>
      Unit(id: json['id'] as int, code: json['code'] as String, name: json['name'] as String);
}

class IngredientCategory {
  const IngredientCategory({required this.id, required this.name});

  final int id;
  final String name;

  factory IngredientCategory.fromJson(Map<String, dynamic> json) =>
      IngredientCategory(id: json['id'] as int, name: json['name'] as String);
}

class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.unit,
    required this.stockMilli,
    required this.minStockMilli,
    required this.avgUnitCost,
    required this.isLowStock,
    required this.isActive,
  });

  final int id;
  final String name;
  final int categoryId;
  final String categoryName;
  final Unit unit;
  final int stockMilli;
  final int minStockMilli;

  /// Costo promedio ponderado (4 decimales, como lo guarda la BD). Solo se muestra.
  final String avgUnitCost;
  final bool isLowStock;
  final bool isActive;

  String get stockLabel => Quantity.format(stockMilli, unit.code);

  /// Costo promedio redondeado a centavos para mostrarlo en Bs.
  String get avgCostLabel {
    final parts = avgUnitCost.split('.');
    final tenThousandths = int.parse(parts[0]) * 10000 + int.parse((parts.length > 1 ? parts[1] : '0').padRight(4, '0'));
    return Money.bob((tenThousandths + 50) ~/ 100);
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) => Ingredient(
        id: json['id'] as int,
        name: json['name'] as String,
        categoryId: (json['category'] as Map)['id'] as int,
        categoryName: (json['category'] as Map)['name'] as String,
        unit: Unit.fromJson(json['unit'] as Map<String, dynamic>),
        stockMilli: Quantity.toMilli(json['current_stock'] as String),
        minStockMilli: Quantity.toMilli(json['min_stock'] as String),
        avgUnitCost: json['avg_unit_cost'] as String,
        isLowStock: json['is_low_stock'] as bool,
        isActive: json['is_active'] as bool,
      );
}

enum MovementType {
  entradaCompra('ENTRADA_COMPRA', 'Compra'),
  salidaConsumo('SALIDA_CONSUMO', 'Consumo'),
  ajuste('AJUSTE', 'Ajuste'),
  reverso('REVERSO', 'Reverso de compra');

  const MovementType(this.api, this.label);

  final String api;
  final String label;

  static MovementType fromApi(String value) => values.firstWhere((t) => t.api == value);
}

class Movement {
  const Movement({
    required this.id,
    required this.ingredientId,
    required this.ingredientName,
    required this.unit,
    required this.type,
    required this.quantityMilli,
    required this.stockAfterMilli,
    required this.createdBy,
    required this.createdAt,
    this.reason,
  });

  final int id;
  final int ingredientId;
  final String ingredientName;
  final String unit;
  final MovementType type;

  /// Con signo: positivo entra, negativo sale.
  final int quantityMilli;
  final int stockAfterMilli;
  final String? reason;
  final String createdBy;
  final String createdAt;

  factory Movement.fromJson(Map<String, dynamic> json) {
    final ingredient = json['ingredient'] as Map<String, dynamic>;
    return Movement(
      id: json['id'] as int,
      ingredientId: ingredient['id'] as int,
      ingredientName: ingredient['name'] as String,
      unit: ingredient['unit'] as String,
      type: MovementType.fromApi(json['type'] as String),
      quantityMilli: Quantity.toMilli(json['quantity'] as String),
      stockAfterMilli: Quantity.toMilli(json['stock_after'] as String),
      reason: json['reason'] as String?,
      createdBy: (json['created_by'] as Map)['full_name'] as String,
      createdAt: json['created_at'] as String,
    );
  }
}
