import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../domain/order.dart';

/// Etiqueta de estado del pedido o del pago, con color.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.color, this.dark = false});

  factory StatusPill.order(OrderStatus status) => StatusPill(status.label, color: switch (status) {
        OrderStatus.pendiente => const Color(0xFFFFE0B2),
        OrderStatus.enPreparacion => AppColors.orange,
        OrderStatus.listo => const Color(0xFFC8E6C9),
        OrderStatus.entregado => const Color(0xFFE0E0E0),
        OrderStatus.cancelado => const Color(0xFFFFCDD2),
      });

  factory StatusPill.payment(String paymentStatus) => switch (paymentStatus) {
        'PAGADO' => const StatusPill('Pagado', color: AppColors.black, dark: true),
        'PARCIAL' => const StatusPill('Pago parcial', color: Color(0xFFFFF59D)),
        _ => const StatusPill('Sin cobrar', color: Color(0xFFFFCDD2)),
      };

  final String label;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dark ? AppColors.white : AppColors.black)),
      );
}
