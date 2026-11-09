import 'package:intl/intl.dart';

import 'dates.dart';

/// Rango de días operativos para filtros (dashboard, reportes, gastos). El API acepta hasta 92 días.
class DayRange {
  const DayRange(this.from, this.to, {this.label});

  static const maxDays = 92;

  final DateTime from;
  final DateTime to;
  final String? label;

  /// Día operativo de hoy en La Paz: antes de las 04:00 todavía es la jornada anterior (corte del backend).
  /// Es la fecha por defecto de ventas, compras y gastos.
  static DateTime today({DateTime? now}) {
    final shifted = (now ?? LaPaz.now()).subtract(const Duration(hours: 4));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  /// Fecha de calendario en La Paz. Entre las 00:00 y las 04:00 es un día después de [today]; el
  /// servidor acepta compras y gastos con esta fecha, así que los rangos deben llegar hasta aquí
  /// para no dejar fuera lo registrado de madrugada.
  static DateTime calendarToday({DateTime? now}) {
    final n = now ?? LaPaz.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DayRange todayRange({DateTime? now}) => presets(now: now).first;

  static List<DayRange> presets({DateTime? now}) {
    final t = today(now: now);
    final last = calendarToday(now: now);
    final yesterday = t.subtract(const Duration(days: 1));
    return [
      DayRange(t, last, label: 'Hoy'),
      DayRange(yesterday, yesterday, label: 'Ayer'),
      DayRange(t.subtract(const Duration(days: 6)), last, label: 'Últimos 7 días'),
      DayRange(DateTime(t.year, t.month, 1), last, label: 'Este mes'),
    ];
  }

  static String api(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Map<String, String> toQuery() => {'from': api(from), 'to': api(to)};

  String get description {
    final f = DateFormat('dd/MM/yyyy');
    final dates = from == to ? f.format(from) : '${f.format(from)} – ${f.format(to)}';
    return label == null ? dates : '$label · $dates';
  }

  @override
  bool operator ==(Object other) => other is DayRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}
