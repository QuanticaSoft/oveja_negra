/// Importes en bolivianos como centavos `int`, nunca `double`: igual que el backend (`Money.php`).
/// El API envía y recibe los importes como texto ("25.50").
class Money {
  Money._();

  static final _amount = RegExp(r'^(-)?(\d{1,10})(?:\.(\d{1,2}))?$');

  /// "25.5" | "25.50" | "25" → centavos. Lanza [FormatException] si no es un importe válido.
  static int toCents(String amount) {
    final match = _amount.firstMatch(amount.trim());
    if (match == null) {
      throw FormatException('Importe inválido', amount);
    }
    final cents = int.parse(match[2]!) * 100 + int.parse((match[3] ?? '0').padRight(2, '0'));
    return match[1] == '-' ? -cents : cents;
  }

  /// Centavos → "25.50", el formato que espera el API.
  static String toApi(int cents) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// Igual que `Money::bob()` del backend: "Bs 3.480" o "Bs 1.250,50".
  static String bob(int cents) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final whole = (abs ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    final fraction = abs % 100;
    return fraction == 0 ? 'Bs $sign$whole' : 'Bs $sign$whole,${fraction.toString().padLeft(2, '0')}';
  }

  /// Texto que escribe el usuario ("12,50", "12.5", "12") → centavos, o null si no es válido.
  static int? parseInput(String input) {
    try {
      return toCents(input.trim().replaceAll(',', '.'));
    } on FormatException {
      return null;
    }
  }
}
