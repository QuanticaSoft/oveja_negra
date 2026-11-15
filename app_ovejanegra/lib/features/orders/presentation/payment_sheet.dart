import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/money.dart';
import '../domain/cart.dart';
import '../domain/order.dart';
import 'qr_payment_screen.dart';

/// Cómo paga el cliente: todo en efectivo, todo por QR, o una parte en efectivo y el resto por QR.
enum PaymentMode { cash, qr, mixed }

/// Hoja de cobro por hasta [dueCents]. En efectivo calcula el vuelto en pantalla (no se envía); con QR
/// muestra el QR del banco con el monto. Devuelve los pagos a registrar, o null si se cierra.
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

class _PaymentSheetState extends State<PaymentSheet> {
  PaymentMode _mode = PaymentMode.cash;
  late final _amount = TextEditingController(text: _plain(widget.dueCents));
  final _cash = TextEditingController();
  final _received = TextEditingController();

  static String _plain(int cents) => Money.toApi(cents).replaceAll('.', ',');

  @override
  void dispose() {
    for (final c in [_amount, _cash, _received]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _receivedCents => _received.text.trim().isEmpty ? null : Money.parseInput(_received.text);

  /// En mixto: lo que paga en efectivo; el QR cubre el resto del saldo.
  int get _cashPart => Money.parseInput(_cash.text) ?? 0;
  int get _qrRemainder => widget.dueCents - _cashPart;
  bool get _mixedValid => _cashPart > 0 && _qrRemainder > 0;

  List<PaymentDraft> get _payments => switch (_mode) {
        PaymentMode.cash => [PaymentDraft(PaymentMethod.efectivo, Money.parseInput(_amount.text) ?? 0, receivedCents: _receivedCents)],
        PaymentMode.qr => [PaymentDraft(PaymentMethod.qr, Money.parseInput(_amount.text) ?? 0)],
        PaymentMode.mixed => [
            PaymentDraft(PaymentMethod.efectivo, _cashPart, receivedCents: _receivedCents),
            PaymentDraft(PaymentMethod.qr, _qrRemainder),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final plan = PaymentPlan(_payments, widget.dueCents);
    final valid = plan.isValid && (_mode != PaymentMode.mixed || _mixedValid);
    final cashDraft = plan.payments.first;
    final error = Theme.of(context).colorScheme.error;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          Text('A cobrar: ${Money.bob(widget.dueCents)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          SegmentedButton<PaymentMode>(
            segments: const [
              ButtonSegment(value: PaymentMode.cash, icon: Icon(Icons.payments_outlined), label: Text('Efectivo')),
              ButtonSegment(value: PaymentMode.qr, icon: Icon(Icons.qr_code_2), label: Text('QR')),
              ButtonSegment(value: PaymentMode.mixed, icon: Icon(Icons.call_split), label: Text('Mixto')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          ...switch (_mode) {
            PaymentMode.cash => [
                _moneyField('payment.amount.0', _amount, 'Monto'),
                const SizedBox(height: 12),
                _receivedField(cashDraft),
              ],
            PaymentMode.qr => [
                _moneyField('payment.amount.0', _amount, 'Monto por QR'),
                const SizedBox(height: 12),
                _showQrButton(Money.parseInput(_amount.text) ?? 0),
              ],
            PaymentMode.mixed => [
                _moneyField('payment.cash', _cash, 'Parte en efectivo'),
                const SizedBox(height: 12),
                _receivedField(cashDraft),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('QR (resto)', style: TextStyle(fontSize: 16)),
                  const Spacer(),
                  Text(_qrRemainder > 0 ? Money.bob(_qrRemainder) : '—',
                      key: const Key('payment.qrRemainder'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                if (_mixedValid)
                  _showQrButton(_qrRemainder)
                else
                  Text('El efectivo debe ser mayor que 0 y menor que ${Money.bob(widget.dueCents)}.', style: TextStyle(color: error)),
              ],
          },
          const SizedBox(height: 8),
          if (plan.overpays)
            Text('El monto supera lo que hay que cobrar.', style: TextStyle(color: error))
          else if (_mode != PaymentMode.mixed && plan.remainingCents > 0)
            Text('Quedará un saldo de ${Money.bob(plan.remainingCents)}.', style: const TextStyle(color: AppColors.grey)),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('payment.confirm'),
            onPressed: valid ? () => Navigator.pop(context, plan.payments) : null,
            child: Text('Cobrar ${Money.bob(plan.paidCents)}'),
          ),
        ]),
      ),
    );
  }

  Widget _moneyField(String key, TextEditingController controller, String label) => TextField(
        key: Key(key),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, prefixText: 'Bs '),
        onChanged: (_) => setState(() {}),
      );

  /// Lo que entrega el cliente en efectivo: solo sirve para el vuelto en pantalla.
  Widget _receivedField(PaymentDraft cash) => TextField(
        key: const Key('payment.received.0'),
        controller: _received,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Recibido en efectivo (opcional)',
          prefixText: 'Bs ',
          helperText: cash.changeCents != null ? 'Vuelto: ${Money.bob(cash.changeCents!)}' : null,
          helperStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.black),
          errorText: cash.receivedIsShort ? 'No alcanza para el monto.' : null,
        ),
        onChanged: (_) => setState(() {}),
      );

  Widget _showQrButton(int cents) => OutlinedButton.icon(
        key: const Key('payment.showQr'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: cents > 0 ? () => showQrPayment(context, amountCents: cents) : null,
        icon: const Icon(Icons.qr_code_2),
        label: Text('Mostrar QR · ${Money.bob(cents)}'),
      );
}
