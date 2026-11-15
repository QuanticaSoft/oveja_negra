import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../data/settings_api.dart';
import '../domain/payment_settings.dart';

final settingsApiProvider = Provider<SettingsApi>((ref) => SettingsApi(ref.watch(apiDioProvider)));

final paymentSettingsProvider =
    FutureProvider.autoDispose<PaymentSettings>((ref) => ref.watch(settingsApiProvider).paymentSettings());
