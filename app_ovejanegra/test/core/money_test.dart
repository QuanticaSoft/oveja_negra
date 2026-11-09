import 'package:flutter_test/flutter_test.dart';
import 'package:ovejanegra/core/utils/money.dart';

void main() {
  test('texto del API ↔ centavos, sin double', () {
    expect(Money.toCents('25.50'), 2550);
    expect(Money.toCents('25.5'), 2550);
    expect(Money.toCents('25'), 2500);
    expect(Money.toCents('-3.05'), -305);
    expect(Money.toApi(2550), '25.50');
    expect(Money.toApi(5), '0.05');
    expect(Money.toApi(-305), '-3.05');
    for (final invalid in ['12.555', '1,50', 'abc', '', '.5']) {
      expect(() => Money.toCents(invalid), throwsFormatException, reason: invalid);
    }
  });

  test('formato Bs igual que Money::bob() del backend', () {
    expect(Money.bob(348000), 'Bs 3.480');
    expect(Money.bob(125050), 'Bs 1.250,50');
    expect(Money.bob(5), 'Bs 0,05');
    expect(Money.bob(123456789), 'Bs 1.234.567,89');
    expect(Money.bob(-2550), 'Bs -25,50');
  });

  test('lo que escribe el usuario acepta coma o punto decimal', () {
    expect(Money.parseInput('12,50'), 1250);
    expect(Money.parseInput(' 12.5 '), 1250);
    expect(Money.parseInput('12'), 1200);
    expect(Money.parseInput('12,555'), isNull);
    expect(Money.parseInput(''), isNull);
  });
}
