import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_view.dart';
import '../../settings/presentation/settings_providers.dart';

/// Muestra el QR del banco en grande con el monto, para que el cliente lo escanee desde su app.
/// El QR es fijo (lo genera el banco): el cliente escribe el monto al pagar y el cajero confirma.
Future<void> showQrPayment(BuildContext context, {required int amountCents}) => Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => QrPaymentScreen(amountCents: amountCents)),
    );

class QrPaymentScreen extends ConsumerWidget {
  const QrPaymentScreen({super.key, required this.amountCents});

  final int amountCents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('Pago con QR')),
      body: SafeArea(
        child: AsyncView(
          value: ref.watch(paymentSettingsProvider),
          onRetry: () => ref.invalidate(paymentSettingsProvider),
          builder: (settings) => ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Monto a pagar', textAlign: TextAlign.center, style: TextStyle(color: AppColors.grey)),
            Text(Money.bob(amountCents),
                key: const Key('qr.amount'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            if (settings.hasQr)
              AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  settings.qrUrlVersioned!,
                  key: const Key('qr.image'),
                  fit: BoxFit.contain,
                  // Sin suavizado: el QR conserva bordes nítidos al agrandarse.
                  filterQuality: FilterQuality.none,
                  errorBuilder: (_, _, _) => const Center(child: Text('No se pudo cargar el QR. Revisa la conexión.')),
                ),
              )
            else
              Container(
                key: const Key('qr.missing'),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(border: Border.all(color: AppColors.orange), borderRadius: BorderRadius.circular(16)),
                child: const Text(
                  'Todavía no hay un QR cargado. El ADMIN lo sube en "Configuración de cobro".',
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
            if (settings.bankName != null || settings.accountHolder != null)
              Text([settings.bankName, settings.accountHolder, settings.accountNumber].whereType<String>().join(' · '),
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Escanea con la app de tu banco y escribe ${Money.bob(amountCents)}.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Volver al cobro')),
          ]),
        ),
      ),
    );
  }
}
