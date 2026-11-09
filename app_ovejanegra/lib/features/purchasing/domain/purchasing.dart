import '../../../core/utils/money.dart';
import '../../../core/utils/quantity.dart';
import '../../orders/domain/order.dart' show PaymentMethod;

class Supplier {
  const Supplier({required this.id, required this.name, required this.isActive, this.phone, this.notes});

  final int id;
  final String name;
  final String? phone;
  final String? notes;
  final bool isActive;

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'] as int,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        notes: json['notes'] as String?,
        isActive: json['is_active'] as bool,
      );
}

class PurchaseItem {
  const PurchaseItem({
    required this.ingredientId,
    required this.ingredientName,
    required this.unit,
    required this.quantityMilli,
    required this.unitPriceCents,
    required this.lineCents,
  });

  final int ingredientId;
  final String ingredientName;
  final String unit;
  final int quantityMilli;
  final int unitPriceCents;
  final int lineCents;

  factory PurchaseItem.fromJson(Map<String, dynamic> json) {
    final ingredient = json['ingredient'] as Map<String, dynamic>;
    return PurchaseItem(
      ingredientId: ingredient['id'] as int,
      ingredientName: ingredient['name'] as String,
      unit: ingredient['unit'] as String,
      quantityMilli: Quantity.toMilli(json['quantity'] as String),
      unitPriceCents: Money.toCents(json['unit_price'] as String),
      lineCents: Money.toCents(json['line_total'] as String),
    );
  }
}

class Purchase {
  const Purchase({
    required this.id,
    required this.purchaseDate,
    required this.paymentMethod,
    required this.items,
    required this.totalCents,
    required this.isVoided,
    required this.createdBy,
    required this.createdAt,
    this.supplierName,
    this.receiptNumber,
    this.voidReason,
  });

  final int id;
  final String purchaseDate;
  final String? supplierName;
  final String? receiptNumber;
  final PaymentMethod paymentMethod;
  final List<PurchaseItem> items;
  final int totalCents;
  final bool isVoided;
  final String? voidReason;
  final String createdBy;
  final String createdAt;

  factory Purchase.fromJson(Map<String, dynamic> json) {
    final voided = json['voided'] as Map<String, dynamic>?;
    return Purchase(
      id: json['id'] as int,
      purchaseDate: json['purchase_date'] as String,
      supplierName: (json['supplier'] as Map?)?['name'] as String?,
      receiptNumber: json['receipt_number'] as String?,
      paymentMethod: PaymentMethod.fromApi(json['payment_method'] as String),
      items: [for (final i in json['items'] as List) PurchaseItem.fromJson(i as Map<String, dynamic>)],
      totalCents: Money.toCents(json['total'] as String),
      isVoided: json['status'] == 'ANULADA',
      voidReason: voided?['reason'] as String?,
      createdBy: (json['created_by'] as Map)['full_name'] as String,
      createdAt: json['created_at'] as String,
    );
  }
}

/// Una línea de la compra en armado. El total se calcula como el backend: round(cantidad × precio, 2).
class PurchaseLineDraft {
  const PurchaseLineDraft({
    required this.ingredientId,
    required this.ingredientName,
    required this.unit,
    required this.quantityMilli,
    required this.unitPriceCents,
  });

  final int ingredientId;
  final String ingredientName;
  final String unit;
  final int quantityMilli;
  final int unitPriceCents;

  int get lineCents => Quantity.lineTotalCents(quantityMilli, unitPriceCents);

  Map<String, dynamic> toApi() => {
        'ingredient_id': ingredientId,
        'quantity': Quantity.toApi(quantityMilli),
        'unit_price': Money.toApi(unitPriceCents),
      };
}
