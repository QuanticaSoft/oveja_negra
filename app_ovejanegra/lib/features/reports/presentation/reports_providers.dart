import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../../../core/utils/date_range.dart';
import '../../finance/data/finance_api.dart';
import '../../finance/domain/finance.dart';
import '../data/reports_api.dart';
import '../domain/reports.dart';

final reportsApiProvider = Provider<ReportsApi>((ref) => ReportsApi(ref.watch(apiDioProvider)));
final financeApiProvider = Provider<FinanceApi>((ref) => FinanceApi(ref.watch(apiDioProvider)));

final dashboardProvider =
    FutureProvider.autoDispose.family<Dashboard, DayRange>((ref, range) => ref.watch(reportsApiProvider).dashboard(range));

final salesDailyProvider =
    FutureProvider.autoDispose.family<List<SalesRow>, DayRange>((ref, range) => ref.watch(reportsApiProvider).salesDaily(range));

final salesMonthlyProvider =
    FutureProvider.autoDispose.family<List<SalesRow>, int>((ref, year) => ref.watch(reportsApiProvider).salesMonthly(year));

final purchasesReportProvider =
    FutureProvider.autoDispose.family<PurchasesReport, DayRange>((ref, range) => ref.watch(reportsApiProvider).purchases(range));

final expensesReportProvider = FutureProvider.autoDispose.family<(int, List<(String, int, int)>), DayRange>(
    (ref, range) => ref.watch(reportsApiProvider).expensesByCategory(range));

final topProductsProvider =
    FutureProvider.autoDispose.family<List<TopProduct>, DayRange>((ref, range) => ref.watch(reportsApiProvider).topProducts(range));

final flowProvider =
    FutureProvider.autoDispose.family<List<FlowDay>, DayRange>((ref, range) => ref.watch(reportsApiProvider).financeFlow(range));

final ledgerProvider =
    FutureProvider.autoDispose.family<List<LedgerEntry>, DayRange>((ref, range) => ref.watch(financeApiProvider).transactions(range));
