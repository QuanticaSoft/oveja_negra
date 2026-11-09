import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/date_range.dart';
import '../domain/finance.dart';

class FinanceApi {
  FinanceApi(this._dio);

  final Dio _dio;

  Future<List<ExpenseCategory>> categories() => apiCall(
        () => _dio.get<dynamic>('/expense-categories'),
        (data) => [for (final c in data as List) ExpenseCategory.fromJson(c as Map<String, dynamic>)],
      );

  Future<void> createCategory(String name) =>
      apiCall(() => _dio.post<dynamic>('/expense-categories', data: {'name': name}), (_) {});

  Future<void> updateCategory(int id, Map<String, dynamic> fields) =>
      apiCall(() => _dio.patch<dynamic>('/expense-categories/$id', data: fields), (_) {});

  /// Por defecto, los últimos 30 días.
  Future<List<Expense>> expenses({String? status}) => apiCall(
        () => _dio.get<dynamic>('/expenses', queryParameters: {'per_page': 100, 'status': ?status}),
        (data) => [for (final e in data as List) Expense.fromJson(e as Map<String, dynamic>)],
      );

  /// [key] se repite en los reintentos: el gasto no se duplica.
  Future<Expense> createExpense(Map<String, dynamic> body, String key) => apiCall(
        () => _dio.post<dynamic>('/expenses', data: body, options: Options(headers: {'Idempotency-Key': key})),
        (data) => Expense.fromJson(data as Map<String, dynamic>),
      );

  Future<void> voidExpense(int id, String reason) =>
      apiCall(() => _dio.post<dynamic>('/expenses/$id/void', data: {'reason': reason}), (_) {});

  Future<List<LedgerEntry>> transactions(DayRange range) => apiCall(
        () => _dio.get<dynamic>('/finance/transactions', queryParameters: {...range.toQuery(), 'per_page': 100}),
        (data) => [for (final t in data as List) LedgerEntry.fromJson(t as Map<String, dynamic>)],
      );
}
