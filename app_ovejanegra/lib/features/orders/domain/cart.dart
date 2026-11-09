import '../../../core/utils/money.dart';
import '../../catalog/domain/catalog.dart';
import 'order.dart';

class CartLine {
  const CartLine({required this.productId, required this.name, required this.unitCents, required this.quantity});

  final int productId;
  final String name;
  final int unitCents;
  final int quantity;

  int get lineCents => unitCents * quantity;

  CartLine withQuantity(int quantity) =>
      CartLine(productId: productId, name: name, unitCents: unitCents, quantity: quantity);
}

/// Pedido en armado. Inmutable y sin widgets: todos los cálculos en centavos `int`.
/// Los precios son orientativos; el total definitivo lo calcula el servidor con los precios de la BD.
class Cart {
  const Cart({
    this.lines = const [],
    this.channel = Channel.local,
    this.discountCents = 0,
    this.customerName = '',
    this.customerPhone = '',
    this.notes = '',
  });

  static const maxQuantity = 99;
  static const maxLines = 50;

  final List<CartLine> lines;
  final Channel channel;
  final int discountCents;
  final String customerName;
  final String customerPhone;
  final String notes;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);
  int get subtotalCents => lines.fold(0, (sum, l) => sum + l.lineCents);
  bool get discountExceedsSubtotal => discountCents > subtotalCents;
  int get totalCents => discountExceedsSubtotal ? 0 : subtotalCents - discountCents;

  int quantityOf(int productId) =>
      lines.where((l) => l.productId == productId).fold(0, (sum, l) => sum + l.quantity);

  Cart add(Product product) {
    final index = lines.indexWhere((l) => l.productId == product.id);
    if (index < 0) {
      if (lines.length >= maxLines) {
        return this;
      }
      return _copy(lines: [
        ...lines,
        CartLine(productId: product.id, name: product.name, unitCents: product.priceCents, quantity: 1),
      ]);
    }
    return setQuantity(product.id, lines[index].quantity + 1);
  }

  /// 0 quita la línea; nunca pasa de [maxQuantity].
  Cart setQuantity(int productId, int quantity) {
    if (quantity <= 0) {
      return _copy(lines: [for (final l in lines) if (l.productId != productId) l]);
    }
    final capped = quantity > maxQuantity ? maxQuantity : quantity;
    return _copy(lines: [for (final l in lines) l.productId == productId ? l.withQuantity(capped) : l]);
  }

  Cart withChannel(Channel channel) => _copy(channel: channel);
  Cart withDiscount(int cents) => _copy(discountCents: cents < 0 ? 0 : cents);
  Cart withCustomer({String? name, String? phone}) => _copy(customerName: name, customerPhone: phone);
  Cart withNotes(String notes) => _copy(notes: notes);

  /// Carrito para editar los ítems de un pedido existente (precios del snapshot del pedido).
  factory Cart.fromOrder(Order order) => Cart(
        channel: order.channel,
        discountCents: order.discountCents,
        lines: [
          for (final i in order.items)
            CartLine(productId: i.productId, name: i.name, unitCents: i.unitCents, quantity: i.quantity),
        ],
      );

  List<Map<String, dynamic>> itemsToApi() => [
        for (final l in lines) {'product_id': l.productId, 'quantity': l.quantity},
      ];

  /// Cuerpo de `POST /v1/orders`. Los campos vacíos no se envían.
  Map<String, dynamic> toApi(List<PaymentDraft> payments) => {
        'channel': channel.api,
        'items': itemsToApi(),
        if (discountCents > 0) 'discount': Money.toApi(discountCents),
        if (customerName.trim().isNotEmpty) 'customer_name': customerName.trim(),
        if (customerPhone.trim().isNotEmpty) 'customer_phone': customerPhone.trim(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (payments.isNotEmpty) 'payments': [for (final p in payments) p.toApi()],
      };

  Cart _copy({List<CartLine>? lines, Channel? channel, int? discountCents, String? customerName, String? customerPhone, String? notes}) =>
      Cart(
        lines: lines ?? this.lines,
        channel: channel ?? this.channel,
        discountCents: discountCents ?? this.discountCents,
        customerName: customerName ?? this.customerName,
        customerPhone: customerPhone ?? this.customerPhone,
        notes: notes ?? this.notes,
      );
}

/// Un pago que se está por registrar. [receivedCents] es lo que entregó el cliente en efectivo:
/// sirve solo para calcular el vuelto en pantalla y nunca se envía al servidor.
class PaymentDraft {
  const PaymentDraft(this.method, this.amountCents, {this.receivedCents});

  final PaymentMethod method;
  final int amountCents;
  final int? receivedCents;

  /// Vuelto a entregar, o null si no aplica o lo recibido no alcanza.
  int? get changeCents {
    if (method != PaymentMethod.efectivo || receivedCents == null || receivedCents! < amountCents) {
      return null;
    }
    return receivedCents! - amountCents;
  }

  bool get receivedIsShort => method == PaymentMethod.efectivo && receivedCents != null && receivedCents! < amountCents;

  Map<String, dynamic> toApi() => {'method': method.api, 'amount': Money.toApi(amountCents)};
}

/// Reglas del cobro antes de enviarlo (el servidor las vuelve a validar).
class PaymentPlan {
  const PaymentPlan(this.payments, this.dueCents);

  final List<PaymentDraft> payments;
  final int dueCents;

  int get paidCents => payments.fold(0, (sum, p) => sum + p.amountCents);
  int get remainingCents => dueCents - paidCents;
  bool get overpays => paidCents > dueCents;
  bool get hasZeroAmount => payments.any((p) => p.amountCents <= 0);
  bool get isValid => payments.isNotEmpty && !overpays && !hasZeroAmount;
}
