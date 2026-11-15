import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/payment_settings.dart';

class SettingsApi {
  SettingsApi(this._dio);

  final Dio _dio;

  Future<PaymentSettings> paymentSettings() => apiCall(
        () => _dio.get<dynamic>('/payment-settings'),
        (data) => PaymentSettings.fromJson(data as Map<String, dynamic>),
      );

  Future<PaymentSettings> updatePaymentSettings(Map<String, dynamic> fields) => apiCall(
        () => _dio.patch<dynamic>('/payment-settings', data: fields),
        (data) => PaymentSettings.fromJson(data as Map<String, dynamic>),
      );

  Future<PaymentSettings> uploadQr(String filePath) => apiCall(
        () async => _dio.post<dynamic>('/payment-settings/qr',
            data: FormData.fromMap({'image': await MultipartFile.fromFile(filePath)})),
        (data) => PaymentSettings.fromJson(data as Map<String, dynamic>),
      );
}
