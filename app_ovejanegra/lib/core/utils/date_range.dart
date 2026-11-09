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
  static DateTime today() {
    final now = LaPaz.now().subtract(const Duration(hours: 4));
    return DateTime(now.year, now.month, now.day);
  }

  static DayRange todayRange() {
    final t = today();
    return DayRange(t, t, label: 'Hoy');
  }

  static List<DayRange> presets() {
    final t = today();
    return [
      DayRange(t, t, label: 'Hoy'),
      DayRange(t.subtract(const Duration(days: 1)), t.subtract(const Duration(days: 1)), label: 'Ayer'),
      DayRange(t.subtract(const Duration(days: 6)), t, label: 'Últimos 7 días'),
      DayRange(DateTime(t.year, t.month, 1), t, label: 'Este mes'),
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
