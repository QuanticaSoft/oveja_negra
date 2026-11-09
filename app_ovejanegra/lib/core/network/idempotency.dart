import 'dart:math';

/// Clave para el header `Idempotency-Key`. Se genera **una vez por operación** (al abrir el
/// formulario o al primer intento) y se reutiliza en cada reintento: así un doble toque o una red
/// inestable no duplican un pedido, un pago, una compra ni un gasto.
class IdempotencyKey {
  IdempotencyKey._();

  static final _random = Random.secure();

  /// UUID v4 (RFC 4122) a partir de 16 bytes aleatorios criptográficamente seguros.
  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
