import 'package:flutter_test/flutter_test.dart';
import 'package:ovejanegra/core/utils/quantity.dart';
import 'package:ovejanegra/features/inventory/domain/inventory.dart';

import '../support/fakes.dart';

void main() {
  test('milésimas ida y vuelta, igual que Quantity.php', () {
    expect(Quantity.toMilli('1.5'), 1500);
    expect(Quantity.toMilli('-0.25'), -250);
    expect(Quantity.toApi(1500), '1.500');
    expect(Quantity.toApi(-5), '-0.005');
    expect(() => Quantity.toMilli('1.2345'), throwsFormatException);
  });

  test('total de línea con el mismo redondeo que el backend y Postgres', () {
    expect(Quantity.lineTotalCents(333, 1005), 335); // 0,333 × 10,05 = 3,34665 → 3,35
    expect(Quantity.lineTotalCents(1, 500), 1); // 0,005 → 0,01
    expect(Quantity.lineTotalCents(1, 499), 0);
    expect(Quantity.lineTotalCents(2500, 4850), 12125);
  });

  test('lo que escribe el usuario y cómo se muestra', () {
    expect(Quantity.parseInput('2,5'), 2500);
    expect(Quantity.parseInput('-0,25'), isNull);
    expect(Quantity.parseInput('-0,25', signed: true), -250);
    expect(Quantity.parseInput('1,2345'), isNull);
    expect(Quantity.format(2500, 'kg'), '2,5 kg');
    expect(Quantity.format(24000, 'unidad'), '24 unidad');
    expect(Quantity.format(1250750), '1.250,75');
    expect(Quantity.format(-250, 'kg'), '-0,25 kg');
  });

  test('insumo del API: stock, mínimo y costo promedio en Bs', () {
    final i = Ingredient.fromJson(ingredientJson(3, 'Carne molida'));
    expect([i.stockMilli, i.minStockMilli, i.stockLabel, i.avgCostLabel], [1500, 2000, '1,5 kg', 'Bs 48,50']);
    final rounded = Ingredient.fromJson({...ingredientJson(3, 'X'), 'avg_unit_cost': '10.3456'});
    expect(rounded.avgCostLabel, 'Bs 10,35');
  });
}
