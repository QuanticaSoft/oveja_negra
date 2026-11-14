import '../../../core/utils/money.dart';
import '../../catalog/domain/catalog.dart';
import 'order.dart';

/// Un extra elegido para una línea (huevo ×2…), con el precio que mostraba la cartilla.
class CartExtra {
  const CartExtra({required this.extraId, required this.name, required this.priceCents, required this.quantity});

  static const maxQuantity = 5;

  final int extraId;
  final String name;
  final int priceCents;
  final int quantity;

  int get totalCents => priceCents * quantity;
}

class CartLine {
  const CartLine({
    required this.productId,
    required this.name,
    required this.unitCents,
    required this.quantity,
    this.notes = '',
    this.extras = const [],
  });

  final int productId;
  final String name;

  /// Precio del producto, sin extras.
  final int unitCents;
  final int quantity;
  final String notes;
  final List<CartExtra> extras;

  int get extrasUnitCents => extras.fold(0, (sum, e) => sum + e.totalCents);
  int get lineCents => (unitCents + extrasUnitCents) * quantity;

  /// Identifica la línea: el mismo producto con otros extras u otra nota es otra línea.
  String get key {
    final sorted = [...extras]..sort((a, b) => a.extraId.compareTo(b.extraId));
    return '$productId|${notes.trim()}|${sorted.map((e) => '${e.extraId}x${e.quantity}').join(',')}';
  }

  /// "+ Huevo ×2, Queso" (vacío si no hay extras).
  String get extrasLabel => extras.isEmpty
      ? ''
      : '+ ${extras.map((e) => e.quantity > 1 ? '${e.name} ×${e.quantity}' : e.name).join(', ')}';

  CartLine withQuantity(int quantity) =>
      CartLine(productId: productId, name: name, unitCents: unitCents, quantity: quantity, notes: notes, extras: extras);

  Map<String, dynamic> toApi() => {
        'product_id': productId,
        'quantity': quantity,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (extras.isNotEmpty) 'extras': [for (final e in extras) {'extra_id': e.extraId, 'quantity': e.quantity}],
      };
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

  /// Unidades de un producto en todas sus líneas (para el contador de la grilla).
  int quantityOf(int productId) =>
      lines.where((l) => l.productId == productId).fold(0, (sum, l) => sum + l.quantity);

  /// Producto sin extras ni nota.
  Cart add(Product product) =>
      addLine(CartLine(productId: product.id, name: product.name, unitCents: product.priceCents, quantity: 1));

  /// Agrega una línea; si ya hay una idéntica (mismo producto, extras y nota), suma la cantidad.
  Cart addLine(CartLine line) {
    final index = lines.indexWhere((l) => l.key == line.key);
    if (index < 0) {
      return lines.length >= maxLines ? this : _copy(lines: [...lines, line]);
    }
    return setQuantity(line.key, lines[index].quantity + line.quantity);
  }

  /// 0 quita la línea; nunca pasa de [maxQuantity].
  Cart setQuantity(String lineKey, int quantity) {
    if (quantity <= 0) {
      return _copy(lines: [for (final l in lines) if (l.key != lineKey) l]);
    }
    final capped = quantity > maxQuantity ? maxQuantity : quantity;
    return _copy(lines: [for (final l in lines) l.key == lineKey ? l.withQuantity(capped) : l]);
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
            CartLine(
              productId: i.productId,
              name: i.name,
              unitCents: i.unitCents,
              quantity: i.quantity,
              notes: i.notes ?? '',
              extras: [
                for (final e in i.extras) CartExtra(extraId: e.extraId, name: e.name, priceCents: e.unitCents, quantity: e.quantity),
              ],
            ),
        ],
      );

  List<Map<String, dynamic>> itemsToApi() => [for (final l in lines) l.toApi()];

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
