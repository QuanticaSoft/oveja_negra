import 'package:flutter_test/flutter_test.dart';
import 'package:ovejanegra/core/network/idempotency.dart';
import 'package:ovejanegra/features/catalog/domain/catalog.dart';
import 'package:ovejanegra/features/orders/domain/cart.dart';
import 'package:ovejanegra/features/orders/domain/order.dart';

import '../../support/fakes.dart';

void main() {
  const burger = Product(id: 10, name: 'Clásica', priceCents: 2550, isAvailable: true);
  const lemonade = Product(id: 20, name: 'Limonada', priceCents: 1000, isAvailable: true);

  test('agrega, junta líneas del mismo producto y calcula en centavos', () {
    final cart = const Cart().add(burger).add(burger).add(lemonade);
    expect(cart.lines.length, 2);
    expect(cart.quantityOf(10), 2);
    expect([cart.itemCount, cart.subtotalCents, cart.totalCents], [3, 6100, 6100]);
  });

  test('cantidad entre 1 y 99; 0 quita la línea', () {
    var cart = const Cart().add(burger);
    cart = cart.setQuantity(cart.lines.single.key, 150);
    expect(cart.quantityOf(10), Cart.maxQuantity);
    cart = cart.setQuantity(cart.lines.single.key, 0);
    expect(cart.isEmpty, isTrue);
  });

  test('descuento: nunca total negativo y avisa si supera el subtotal', () {
    final cart = const Cart().add(burger).withDiscount(550);
    expect(cart.totalCents, 2000);
    final excessive = cart.withDiscount(3000);
    expect([excessive.discountExceedsSubtotal, excessive.totalCents], [true, 0]);
    expect(cart.withDiscount(-5).discountCents, 0);
  });

  test('cuerpo para el API: importes como texto y sin campos vacíos', () {
    final cart = const Cart()
        .add(burger)
        .add(burger)
        .withChannel(Channel.whatsapp)
        .withDiscount(100)
        .withCustomer(name: '  Ana ', phone: '');
    expect(cart.toApi([const PaymentDraft(PaymentMethod.qr, 5000)]), {
      'channel': 'WHATSAPP',
      'items': [
        {'product_id': 10, 'quantity': 2},
      ],
      'discount': '1.00',
      'customer_name': 'Ana',
      'payments': [
        {'method': 'QR', 'amount': '50.00'},
      ],
    });
  });

  test('delivery: el envío se suma después del descuento y solo cuenta en DELIVERY', () {
    var cart = const Cart().add(burger).add(burger).withDiscount(100).withDelivery(feeCents: 500, address: ' Av. Busch 123 ');
    expect(cart.totalCents, 5000, reason: 'sin DELIVERY el envío escrito no se cobra');
    expect(cart.toApi(const []).containsKey('delivery'), isFalse);

    cart = cart.withFulfillment(Fulfillment.delivery);
    expect([cart.subtotalCents, cart.effectiveDeliveryFeeCents, cart.totalCents], [5100, 500, 5500]);
    expect(cart.withDiscount(9999).totalCents, 500, reason: 'el descuento excesivo no anula el envío');
    expect(cart.toApi(const [])['fulfillment'], 'DELIVERY');
    expect(cart.toApi(const [])['delivery'], {'address': 'Av. Busch 123', 'fee': '5.00'});

    expect(cart.withDelivery(address: '  ').deliveryIncomplete, isTrue);
    expect(cart.withFulfillment(Fulfillment.recoger).toApi(const [])['fulfillment'], 'RECOGER');
  });

  test('pedido delivery del API: envío, dirección y carrito de edición', () {
    final order = Order.fromJson({
      ...orderJson(total: '56.00'),
      'subtotal': '51.00',
      'fulfillment': 'DELIVERY',
      'delivery_fee': '5.00',
      'delivery': {'address': 'Av. Busch 123', 'references': 'Portón verde', 'lat': '-16.500000', 'lng': '-68.100000'},
    });
    expect([order.fulfillment, order.deliveryFeeCents, order.totalCents], [Fulfillment.delivery, 500, 5600]);
    expect([order.delivery!.address, order.delivery!.references, order.delivery!.hasLocation], ['Av. Busch 123', 'Portón verde', true]);
    expect(Cart.fromOrder(order).totalCents, 5600);
  });

  test('vuelto en efectivo y reglas del cobro mixto', () {
    expect(const PaymentDraft(PaymentMethod.efectivo, 5100, receivedCents: 10000).changeCents, 4900);
    expect(const PaymentDraft(PaymentMethod.efectivo, 5100, receivedCents: 5000).receivedIsShort, isTrue);
    expect(const PaymentDraft(PaymentMethod.qr, 5100, receivedCents: 10000).changeCents, isNull);

    final mixed = PaymentPlan(const [PaymentDraft(PaymentMethod.efectivo, 3000), PaymentDraft(PaymentMethod.qr, 2100)], 5100);
    expect([mixed.isValid, mixed.remainingCents], [true, 0]);
    expect(const PaymentPlan([PaymentDraft(PaymentMethod.qr, 6000)], 5100).overpays, isTrue);
    expect(const PaymentPlan([PaymentDraft(PaymentMethod.qr, 0)], 5100).isValid, isFalse);
    expect(const PaymentPlan([PaymentDraft(PaymentMethod.qr, 2000)], 5100).remainingCents, 3100);
  });

  test('la misma operación conserva su clave; otro contenido u otra venta llevan otra', () {
    final op = IdempotentOperation();
    final a = op.keyFor({'items': 1});
    expect(op.keyFor({'items': 1}), a);
    final b = op.keyFor({'items': 2});
    expect(b, isNot(a));
    op.done();
    expect(op.keyFor({'items': 2}), isNot(b));
  });

  test('pedido del API: importes, estados y reglas de edición', () {
    final order = Order.fromJson({
      ...orderJson(total: '51.00', paid: '20.00', paymentStatus: 'PARCIAL', payments: [paymentJson(1, 'EFECTIVO', '20.00')]),
    });
    expect([order.totalCents, order.paidCents, order.balanceCents], [5100, 2000, 3100]);
    expect(order.payments.single.method, PaymentMethod.efectivo);
    expect(order.itemsEditable, isFalse, reason: 'tiene pagos');
    expect(Order.fromJson(orderJson()).itemsEditable, isTrue);
    expect(OrderStatus.pendiente.next, [OrderStatus.enPreparacion, OrderStatus.listo, OrderStatus.entregado]);
    expect(OrderStatus.entregado.next, isEmpty);
    expect(OrderStatus.cancelado.next, isEmpty);
    expect(Cart.fromOrder(order).quantityOf(10), 2);
  });

  test('extras: precio por unidad, líneas separadas por extras/nota y unión de líneas idénticas', () {
    const egg = CartExtra(extraId: 1, name: 'Huevo', priceCents: 400, quantity: 2);
    const withEgg = CartLine(productId: 10, name: 'Clásica', unitCents: 2550, quantity: 1, notes: 'sin cebolla', extras: [egg]);
    var cart = const Cart().addLine(withEgg).addLine(withEgg).add(burger);

    expect(cart.lines.length, 2, reason: 'la Clásica sola es otra línea');
    expect(cart.lines.first.quantity, 2, reason: 'dos líneas idénticas se juntan');
    // (25,50 + 2 × 4) × 2 + 25,50 = 92,50
    expect([cart.lines.first.extrasUnitCents, cart.lines.first.lineCents, cart.subtotalCents], [800, 6700, 9250]);
    expect(cart.quantityOf(10), 3);
    expect(cart.lines.first.extrasLabel, '+ Huevo ×2');

    expect(cart.itemsToApi(), [
      {'product_id': 10, 'quantity': 2, 'notes': 'sin cebolla', 'extras': [{'extra_id': 1, 'quantity': 2}]},
      {'product_id': 10, 'quantity': 1},
    ]);

    cart = cart.setQuantity(cart.lines.first.key, 0);
    expect(cart.lines.single.extras, isEmpty);
  });

  test('pedido con extras del API → carrito de edición con los mismos extras y nota', () {
    final base = orderJson();
    final order = Order.fromJson({
      ...base,
      'items': [
        {
          ...((base['items'] as List).first as Map<String, dynamic>),
          'notes': 'término medio',
          'line_total': '59.00',
          'extras_unit_total': '4.00',
          'extras': [
            {'extra_id': 1, 'name': 'Huevo', 'unit_price': '4.00', 'quantity': 1},
          ],
        },
      ],
    });
    expect([order.items.single.extrasLabel, order.items.single.notes], ['+ Huevo', 'término medio']);
    final line = Cart.fromOrder(order).lines.single;
    expect([line.extrasUnitCents, line.notes, line.lineCents], [400, 'término medio', 5900]);
  });
}
