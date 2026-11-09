import 'package:flutter/foundation.dart';

/// URL base del API, siempre con `/v1`. Se fija al compilar:
/// `flutter run --dart-define=API_BASE_URL=https://www.quanticasoft.com/oveja_negra/api-staging/v1`.
/// Sin define apunta al API de dev: 10.0.2.2 es el Mac visto desde el emulador de Android.
class Env {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8082/v1',
  );

  /// Un build de release nunca debe hablar con el API por HTTP sin cifrar.
  static void assertSafe() {
    if (kReleaseMode && !apiBaseUrl.startsWith('https://')) {
      throw StateError('API_BASE_URL debe ser https en release: $apiBaseUrl');
    }
  }
}
