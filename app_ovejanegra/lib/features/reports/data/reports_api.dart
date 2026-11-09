import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/money.dart';
import '../domain/reports.dart';

class ReportsApi {
  ReportsApi(this._dio);

  final Dio _dio;

  Future<Dashboard> dashboard(DayRange range) => apiCall(
        () => _dio.get<dynamic>('/dashboard', queryParameters: range.toQuery()),
        (data) => Dashboard.fromJson(data as Map<String, dynamic>),
      );

  Future<List<SalesRow>> salesDaily(DayRange range) => apiCall(
        () => _dio.get<dynamic>('/reports/sales/daily', queryParameters: range.toQuery()),
        (data) => [for (final r in data as List) SalesRow.fromJson(r as Map<String, dynamic>)],
      );

  Future<List<SalesRow>> salesMonthly(int year) => apiCall(
        () => _dio.get<dynamic>('/reports/sales/monthly', queryParameters: {'year': year}),
        (data) => [for (final r in (data as Map)['months'] as List) SalesRow.fromJson(r as Map<String, dynamic>)],
      );

  Future<PurchasesReport> purchases(DayRange range) => apiCall(
        () => _dio.get<dynamic>('/reports/purchases', queryParameters: range.toQuery()),
        (data) => PurchasesReport.fromJson(data as Map<String, dynamic>),
      );

  /// (categoría, n.º de gastos, total) y el total general.
  Future<(int, List<(String, int, int)>)> expensesByCategory(DayRange range) => apiCall(
        () => _dio.get<dynamic>('/reports/expenses/by-category', queryParameters: range.toQuery()),
        (data) {
          final map = data as Map;
          return (
            Money.toCents(map['total'] as String),
            [
              for (final c in (map['categories'] as List).cast<Map>())
                ((c['category'] as Map)['name'] as String, c['expenses'] as int, Money.toCents(c['total'] as String)),
            ],
          );
        },
      );

  Future<List<TopProduct>> topProducts(DayRange range, {int limit = 20}) => apiCall(
        () => _dio.get<dynamic>('/reports/products/top', queryParameters: {...range.toQuery(), 'limit': limit}),
        (data) => [for (final p in (data as Map)['products'] as List) TopProduct.fromJson(p as Map<String, dynamic>)],
      );

  Future<List<FlowDay>> financeFlow(DayRange range) => apiCall(
        () => _dio.get<dynamic>('/reports/finance/movements', queryParameters: range.toQuery()),
        (data) => [for (final d in (data as Map)['days'] as List) FlowDay.fromJson(d as Map<String, dynamic>)],
      );
}
