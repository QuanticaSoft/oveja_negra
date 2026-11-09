import 'package:flutter_test/flutter_test.dart';
import 'package:ovejanegra/core/utils/date_range.dart';

void main() {
  // `now` es hora de pared de La Paz.
  final madrugada = DateTime(2026, 11, 9, 0, 56);
  final tarde = DateTime(2026, 11, 9, 15, 0);

  test('de madrugada la jornada sigue siendo la del día anterior; el calendario ya cambió', () {
    expect(DayRange.today(now: madrugada), DateTime(2026, 11, 8));
    expect(DayRange.calendarToday(now: madrugada), DateTime(2026, 11, 9));
    expect(DayRange.today(now: tarde), DateTime(2026, 11, 9));
    expect(DayRange.today(now: DateTime(2026, 11, 9, 4, 0)), DateTime(2026, 11, 9), reason: 'el corte es a las 04:00');
  });

  test('los rangos llegan hasta la fecha de calendario: no dejan fuera lo registrado de madrugada', () {
    final presets = DayRange.presets(now: madrugada);
    final byLabel = {for (final p in presets) p.label!: p};
    expect(byLabel['Hoy']!.toQuery(), {'from': '2026-11-08', 'to': '2026-11-09'});
    expect(byLabel['Ayer']!.toQuery(), {'from': '2026-11-07', 'to': '2026-11-07'});
    expect(byLabel['Últimos 7 días']!.toQuery(), {'from': '2026-11-02', 'to': '2026-11-09'});
    expect(byLabel['Este mes']!.toQuery(), {'from': '2026-11-01', 'to': '2026-11-09'});

    // De tarde, "Hoy" es un solo día.
    expect(DayRange.presets(now: tarde).first.toQuery(), {'from': '2026-11-09', 'to': '2026-11-09'});
  });
}
