import '../../../core/utils/money.dart';

enum OrderStatus {
  pendiente('PENDIENTE', 'Pendiente'),
  enPreparacion('EN_PREPARACION', 'En preparación'),
  listo('LISTO', 'Listo'),
  entregado('ENTREGADO', 'Entregado'),
  cancelado('CANCELADO', 'Cancelado');

  const OrderStatus(this.api, this.label);

  final String api;
  final String label;

  static OrderStatus fromApi(String value) => values.firstWhere((s) => s.api == value);

  /// Flujo de cocina: solo hacia adelante, se pueden saltar pasos. CANCELADO va por su endpoint.
  static const flow = [pendiente, enPreparacion, listo, entregado];

  static const open = {pendiente, enPreparacion, listo};

  /// Estados a los que puede avanzar desde este.
  List<OrderStatus> get next => this == cancelado ? const [] : flow.sublist(flow.indexOf(this) + 1);
}

enum PaymentMethod {
  efectivo('EFECTIVO', 'Efectivo'),
  qr('QR', 'QR');

  const PaymentMethod(this.api, this.label);

  final String api;
  final String label;

  static PaymentMethod fromApi(String value) => values.firstWhere((m) => m.api == value);
}

enum Channel {
  local('LOCAL', 'Local'),
  whatsapp('WHATSAPP', 'WhatsApp');

  const Channel(this.api, this.label);

  final String api;
  final String label;

  static Channel fromApi(String value) => values.firstWhere((c) => c.api == value);
}

class OrderItem {
  const OrderItem({required this.productId, required this.name, required this.unitCents, required this.quantity, required this.lineCents});

  final int productId;
  final String name;
  final int unitCents;
  final int quantity;
  final int lineCents;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        productId: json['product_id'] as int,
        name: json['name'] as String,
        unitCents: Money.toCents(json['unit_price'] as String),
        quantity: json['quantity'] as int,
        lineCents: Money.toCents(json['line_total'] as String),
      );
}

class Payment {
  const Payment({
    required this.id,
    required this.method,
    required this.amountCents,
    required this.isVoided,
    required this.receivedBy,
    required this.createdAt,
    this.voidReason,
  });

  final int id;
  final PaymentMethod method;
  final int amountCents;
  final bool isVoided;
  final String receivedBy;
  final String createdAt;
  final String? voidReason;

  factory Payment.fromJson(Map<String, dynamic> json) {
    final voided = json['voided'] as Map<String, dynamic>?;
    return Payment(
      id: json['id'] as int,
      method: PaymentMethod.fromApi(json['method'] as String),
      amountCents: Money.toCents(json['amount'] as String),
      isVoided: json['status'] == 'ANULADO',
      receivedBy: (json['received_by'] as Map)['full_name'] as String,
      createdAt: json['created_at'] as String,
      voidReason: voided?['reason'] as String?,
    );
  }
}

class Order {
  const Order({
    required this.id,
    required this.number,
    required this.businessDate,
    required this.channel,
    required this.status,
    required this.items,
    required this.subtotalCents,
    required this.discountCents,
    required this.totalCents,
    required this.paidCents,
    required this.balanceCents,
    required this.paymentStatus,
    required this.createdBy,
    required this.createdAt,
    this.customerName,
    this.customerPhone,
    this.notes,
    this.cancelReason,
    this.payments = const [],
  });

  final int id;
  final int number;
  final String businessDate;
  final Channel channel;
  final OrderStatus status;
  final String? customerName;
  final String? customerPhone;
  final String? notes;
  final List<OrderItem> items;
  final int subtotalCents;
  final int discountCents;
  final int totalCents;
  final int paidCents;
  final int balanceCents;

  /// SIN_PAGAR | PARCIAL | PAGADO, calculado por el servidor con los pagos confirmados.
  final String paymentStatus;
  final String createdBy;
  final String createdAt;
  final String? cancelReason;

  /// Solo en el detalle (`GET /orders/{id}`).
  final List<Payment> payments;

  bool get isPaid => paymentStatus == 'PAGADO';

  /// Igual que el trigger de la BD: los ítems solo cambian con el pedido PENDIENTE y sin pagos.
  bool get itemsEditable => status == OrderStatus.pendiente && paidCents == 0;

  factory Order.fromJson(Map<String, dynamic> json) {
    final cancelled = json['cancelled'] as Map<String, dynamic>?;
    return Order(
      id: json['id'] as int,
      number: json['number'] as int,
      businessDate: json['business_date'] as String,
      channel: Channel.fromApi(json['channel'] as String),
      status: OrderStatus.fromApi(json['status'] as String),
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      notes: json['notes'] as String?,
      items: [for (final i in json['items'] as List) OrderItem.fromJson(i as Map<String, dynamic>)],
      subtotalCents: Money.toCents(json['subtotal'] as String),
      discountCents: Money.toCents(json['discount'] as String),
      totalCents: Money.toCents(json['total'] as String),
      paidCents: Money.toCents(json['paid'] as String),
      balanceCents: Money.toCents(json['balance'] as String),
      paymentStatus: json['payment_status'] as String,
      createdBy: (json['created_by'] as Map)['full_name'] as String,
      createdAt: json['created_at'] as String,
      cancelReason: cancelled?['reason'] as String?,
      payments: [for (final p in json['payments'] as List? ?? const []) Payment.fromJson(p as Map<String, dynamic>)],
    );
  }
}
