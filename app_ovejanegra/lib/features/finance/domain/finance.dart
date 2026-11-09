import '../../../core/utils/money.dart';
import '../../orders/domain/order.dart' show PaymentMethod;

class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.name, required this.isActive});

  final int id;
  final String name;
  final bool isActive;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseCategory(id: json['id'] as int, name: json['name'] as String, isActive: json['is_active'] as bool);
}

class Expense {
  const Expense({
    required this.id,
    required this.date,
    required this.categoryName,
    required this.description,
    required this.amountCents,
    required this.method,
    required this.isVoided,
    required this.createdBy,
    this.voidReason,
  });

  final int id;
  final String date;
  final String categoryName;
  final String description;
  final int amountCents;
  final PaymentMethod method;
  final bool isVoided;
  final String? voidReason;
  final String createdBy;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as int,
        date: json['expense_date'] as String,
        categoryName: (json['category'] as Map)['name'] as String,
        description: json['description'] as String,
        amountCents: Money.toCents(json['amount'] as String),
        method: PaymentMethod.fromApi(json['payment_method'] as String),
        isVoided: json['status'] == 'ANULADO',
        voidReason: (json['voided'] as Map?)?['reason'] as String?,
        createdBy: (json['created_by'] as Map)['full_name'] as String,
      );
}

/// Fila del libro financiero.
class LedgerEntry {
  const LedgerEntry({
    required this.isIncome,
    required this.category,
    required this.description,
    required this.amountCents,
    required this.businessDate,
    required this.sourceType,
    required this.isReversal,
  });

  final bool isIncome;
  final String category;
  final String description;
  final int amountCents;
  final String businessDate;
  final String sourceType;
  final bool isReversal;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        isIncome: json['type'] == 'INGRESO',
        category: json['category'] as String,
        description: json['description'] as String,
        amountCents: Money.toCents(json['amount'] as String),
        businessDate: json['business_date'] as String,
        sourceType: (json['source'] as Map)['type'] as String,
        isReversal: json['is_reversal'] as bool,
      );
}
