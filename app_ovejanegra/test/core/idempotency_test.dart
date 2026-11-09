import 'package:flutter_test/flutter_test.dart';
import 'package:ovejanegra/core/network/idempotency.dart';

void main() {
  test('genera UUID v4 que acepta el backend y no se repiten', () {
    final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final keys = {for (var i = 0; i < 1000; i++) IdempotencyKey.generate()};
    expect(keys.length, 1000);
    expect(keys.every(uuid.hasMatch), isTrue);
  });
}
