import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/money.dart';

/// Atajos de fecha (Hoy, Ayer, 7 días, Este mes) y un rango personalizado de hasta 92 días.
class DateRangeBar extends StatelessWidget {
  const DateRangeBar({super.key, required this.value, required this.onChanged});

  final DayRange value;
  final ValueChanged<DayRange> onChanged;

  Future<void> _custom(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026),
      lastDate: DayRange.calendarToday(),
      initialDateRange: DateTimeRange(start: value.from, end: value.to),
    );
    if (picked == null) {
      return;
    }
    if (picked.end.difference(picked.start).inDays >= DayRange.maxDays) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('El rango máximo es de ${DayRange.maxDays} días.')));
      }
      return;
    }
    onChanged(DayRange(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
        for (final preset in DayRange.presets())
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(preset.label!), selected: preset == value, onSelected: (_) => onChanged(preset)),
          ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(value.label == null ? value.description : 'Elegir fechas'),
          onPressed: () => _custom(context),
        ),
      ]),
    );
  }
}

/// Indicador grande: título, importe y un detalle opcional.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.detail, this.color, this.width = 170});

  final String label;
  final String value;
  final String? detail;
  final Color? color;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
              if (detail != null) Text(detail!, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      );
}

/// Barras verticales por período. Los importes llegan en centavos; `double` se usa **solo** para dibujar.
class AmountBarChart extends StatelessWidget {
  const AmountBarChart({super.key, required this.labels, required this.series, this.height = 220});

  final List<String> labels;

  /// Una o dos series (p. ej. vendido y cobrado), en centavos, con su color.
  final List<(List<int>, Color)> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final step = labels.length > 12 ? (labels.length / 8).ceil() : 1;
    return SizedBox(
      height: height,
      child: BarChart(BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length || i % step != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(meta: meta, child: Text(labels[i], style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.black,
            getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
              '${labels[group.x]}\n${Money.bob(series[rodIndex].$1[group.x])}',
              const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < labels.length; i++)
            BarChartGroupData(x: i, barsSpace: 2, barRods: [
              for (final (values, color) in series)
                BarChartRodData(
                  toY: values[i] / 100,
                  color: color,
                  width: labels.length > 15 ? 4 : 10,
                  borderRadius: BorderRadius.circular(2),
                ),
            ]),
        ],
      )),
    );
  }
}

/// Línea del acumulado (flujo financiero). `double` solo para dibujar.
class CumulativeLineChart extends StatelessWidget {
  const CumulativeLineChart({super.key, required this.values, this.height = 200});

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: LineChart(LineChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.black,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(Money.bob(values[s.x.toInt()]), const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i] / 100)],
              color: AppColors.orange,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
          ],
        )),
      );
}

/// Barras horizontales simples (proporción del mayor), para rankings y categorías.
class ProportionBars extends StatelessWidget {
  const ProportionBars({super.key, required this.rows});

  /// (etiqueta, valor para la proporción, texto a la derecha)
  final List<(String, int, String)> rows;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<int>(0, (m, r) => r.$2 > m ? r.$2 : m);
    return Column(children: [
      for (final (label, value, trailing) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
              Text(trailing, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : value / max,
                minHeight: 8,
                color: AppColors.orange,
                backgroundColor: const Color(0xFFEDEDED),
              ),
            ),
          ]),
        ),
    ]);
  }
}
