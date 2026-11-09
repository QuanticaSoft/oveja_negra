import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/money.dart';
import '../domain/cart.dart';
import '../domain/order.dart';

/// Hoja de cobro: uno o varios pagos (efectivo + QR) por hasta [dueCents]. En efectivo, lo que
/// entrega el cliente calcula el vuelto en pantalla. Devuelve los pagos o null si se cierra.
Future<List<PaymentDraft>?> showPaymentSheet(BuildContext context, {required int dueCents, required String title}) {
  return showModalBottomSheet<List<PaymentDraft>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PaymentSheet(dueCents: dueCents, title: title),
  );
}

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({super.key, required this.dueCents, required this.title});

  final int dueCents;
  final String title;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _Row {
  _Row(this.method, int cents) : amount = TextEditingController(text: _plain(cents));

  PaymentMethod method;
  final TextEditingController amount;
  final received = TextEditingController();

  static String _plain(int cents) => Money.toApi(cents).replaceAll('.', ',');

  PaymentDraft draft() => PaymentDraft(
        method,
        Money.parseInput(amount.text) ?? 0,
        receivedCents: method == PaymentMethod.efectivo ? Money.parseInput(received.text) : null,
      );

  void dispose() {
    amount.dispose();
    received.dispose();
  }
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final List<_Row> _rows = [_Row(PaymentMethod.efectivo, widget.dueCents)];

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  PaymentPlan get _plan => PaymentPlan([for (final r in _rows) r.draft()], widget.dueCents);

  void _addRow() {
    final remaining = _plan.remainingCents;
    final other = _rows.first.method == PaymentMethod.efectivo ? PaymentMethod.qr : PaymentMethod.efectivo;
    setState(() => _rows.add(_Row(other, remaining > 0 ? remaining : 0)));
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final error = Theme.of(context).colorScheme.error;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            Text('A cobrar: ${Money.bob(widget.dueCents)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            for (var i = 0; i < _rows.length; i++) _paymentRow(i),
            if (_rows.length < 5 && plan.remainingCents > 0)
              TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const Text('Agregar otro pago (mixto)')),
            const SizedBox(height: 8),
            if (plan.overpays)
              Text('Los pagos superan lo que hay que cobrar.', style: TextStyle(color: error))
            else if (plan.remainingCents > 0)
              Text('Quedará un saldo de ${Money.bob(plan.remainingCents)}.', style: const TextStyle(color: AppColors.grey)),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('payment.confirm'),
              onPressed: plan.isValid ? () => Navigator.pop(context, plan.payments) : null,
              child: Text('Cobrar ${Money.bob(plan.paidCents)}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentRow(int index) {
    final row = _rows[index];
    final draft = row.draft();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: SegmentedButton<PaymentMethod>(
                segments: [for (final m in PaymentMethod.values) ButtonSegment(value: m, label: Text(m.label))],
                selected: {row.method},
                onSelectionChanged: (s) => setState(() => row.method = s.first),
              ),
            ),
            if (_rows.length > 1)
              IconButton(
                tooltip: 'Quitar pago',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _rows.removeAt(index).dispose()),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            key: Key('payment.amount.$index'),
            controller: row.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Monto', prefixText: 'Bs '),
            onChanged: (_) => setState(() {}),
          ),
          if (row.method == PaymentMethod.efectivo) ...[
            const SizedBox(height: 12),
            TextField(
              key: Key('payment.received.$index'),
              controller: row.received,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Recibido del cliente (opcional)',
                prefixText: 'Bs ',
                helperText: draft.changeCents != null ? 'Vuelto: ${Money.bob(draft.changeCents!)}' : null,
                helperStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.black),
                errorText: draft.receivedIsShort ? 'No alcanza para el monto.' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ]),
      ),
    );
  }
}
