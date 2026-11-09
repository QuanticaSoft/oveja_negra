/// Cantidades de insumo (hasta 3 decimales) como milésimas `int`, igual que `Quantity.php`.
class Quantity {
  Quantity._();

  static final _quantity = RegExp(r'^(-)?(\d{1,9})(?:\.(\d{1,3}))?$');

  /// "2.5" | "-0.250" → milésimas. Lanza [FormatException] si no es válida.
  static int toMilli(String quantity) {
    final match = _quantity.firstMatch(quantity.trim());
    if (match == null) {
      throw FormatException('Cantidad inválida', quantity);
    }
    final milli = int.parse(match[2]!) * 1000 + int.parse((match[3] ?? '0').padRight(3, '0'));
    return match[1] == '-' ? -milli : milli;
  }

  /// Milésimas → "2.500", el formato que espera el API.
  static String toApi(int milli) {
    final sign = milli < 0 ? '-' : '';
    final abs = milli.abs();
    return '$sign${abs ~/ 1000}.${(abs % 1000).toString().padLeft(3, '0')}';
  }

  /// Para mostrar: "2,5 kg", "24 unidad", "1.250,75 g" (sin ceros de más).
  static String format(int milli, [String? unit]) {
    final sign = milli < 0 ? '-' : '';
    final abs = milli.abs();
    final whole = (abs ~/ 1000).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    final fraction = (abs % 1000).toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
    final number = fraction.isEmpty ? '$sign$whole' : '$sign$whole,$fraction';
    return unit == null ? number : '$number $unit';
  }

  /// Lo que escribe el usuario ("2,5", "-0.25") → milésimas, o null si no es válido.
  static int? parseInput(String input, {bool signed = false}) {
    try {
      final milli = toMilli(input.trim().replaceAll(',', '.'));
      return !signed && milli < 0 ? null : milli;
    } on FormatException {
      return null;
    }
  }

  /// `round(cantidad × precio, 2)` en centavos, con el mismo redondeo que Postgres y el backend.
  static int lineTotalCents(int milli, int unitPriceCents) => (milli * unitPriceCents + 500) ~/ 1000;
}
