import 'package:intl/intl.dart';

/// Fechas del negocio en hora de La Paz. Bolivia está en UTC−4 todo el año (sin horario de verano),
/// así que no hace falta una base de datos de zonas horarias: basta con restar 4 horas a UTC.
class LaPaz {
  LaPaz._();

  static const offset = Duration(hours: -4);

  /// Instante (ISO 8601 del API, con zona) → hora de pared en La Paz.
  static DateTime fromApi(String iso) => DateTime.parse(iso).toUtc().add(offset);

  static DateTime now() => DateTime.now().toUtc().add(offset);

  /// "08/11/2026 21:30"
  static String dateTime(String iso) => DateFormat('dd/MM/yyyy HH:mm', 'es').format(fromApi(iso));

  /// Fecha del API ("2026-11-08", sin hora) → "08/11/2026".
  static String date(String ymd) => DateFormat('dd/MM/yyyy', 'es').format(DateTime.parse(ymd));
}
