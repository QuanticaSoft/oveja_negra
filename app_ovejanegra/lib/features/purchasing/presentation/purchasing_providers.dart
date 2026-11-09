import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../data/purchasing_api.dart';
import '../domain/purchasing.dart';

final purchasingApiProvider = Provider<PurchasingApi>((ref) => PurchasingApi(ref.watch(apiDioProvider)));

final purchasesProvider =
    FutureProvider.autoDispose.family<List<Purchase>, String?>((ref, status) => ref.watch(purchasingApiProvider).purchases(status: status));

final purchaseProvider = FutureProvider.autoDispose.family<Purchase, int>((ref, id) => ref.watch(purchasingApiProvider).purchase(id));

final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>((ref) => ref.watch(purchasingApiProvider).suppliers());
