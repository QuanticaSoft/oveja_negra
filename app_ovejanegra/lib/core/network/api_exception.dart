import 'package:dio/dio.dart';

/// Error del API (`{"error": {"code", "message", "details"}}`) o de red, en un solo tipo.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status, this.details = const {}});

  static const network = 'NETWORK_ERROR';

  final String code;
  final String message;
  final int? status;

  /// Errores por campo (`{"items.0.quantity": "…"}`) u otros datos del error (`balance`, `products`…).
  final Map<String, dynamic> details;

  bool get isNetwork => code == network;

  /// Mensaje de un campo concreto, para mostrarlo junto al campo del formulario.
  String? fieldError(String field) => details[field] is String ? details[field] as String : null;

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final error = data['error'] as Map;
      return ApiException(
        error['code'] as String? ?? 'UNKNOWN',
        error['message'] as String? ?? 'Error inesperado.',
        status: e.response?.statusCode,
        details: error['details'] is Map ? Map<String, dynamic>.from(error['details'] as Map) : const {},
      );
    }
    if (e.response == null) {
      return const ApiException(network, 'No hay conexión con el servidor. Revisa la red e intenta de nuevo.');
    }
    return ApiException('HTTP_${e.response!.statusCode}', 'El servidor respondió con un error inesperado.',
        status: e.response!.statusCode);
  }

  @override
  String toString() => 'ApiException($code, $message)';
}

/// Ejecuta una llamada y convierte cualquier [DioException] en [ApiException].
Future<T> apiCall<T>(Future<Response<dynamic>> Function() call, T Function(dynamic data) parse) async {
  try {
    final response = await call();
    return parse((response.data as Map)['data']);
  } on DioException catch (e) {
    if (e.error is ApiException) {
      throw e.error as ApiException;
    }
    throw ApiException.fromDio(e);
  }
}
