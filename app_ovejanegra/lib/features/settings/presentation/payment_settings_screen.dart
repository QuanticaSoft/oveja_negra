import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../domain/payment_settings.dart';
import 'settings_providers.dart';

/// Configuración de cobro (`settings.manage`): datos de la cuenta y la imagen del QR que genera la
/// app o banca del banco. Todos los teléfonos la ven al cobrar con QR.
class PaymentSettingsScreen extends ConsumerWidget {
  const PaymentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncView(
        value: ref.watch(paymentSettingsProvider),
        onRetry: () => ref.invalidate(paymentSettingsProvider),
        builder: (settings) => _Form(settings: settings),
      );
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.settings});

  final PaymentSettings settings;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _bank = TextEditingController(text: widget.settings.bankName);
  late final _holder = TextEditingController(text: widget.settings.accountHolder);
  late final _account = TextEditingController(text: widget.settings.accountNumber);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_bank, _holder, _account]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(paymentSettingsProvider);
      if (mounted) {
        showMessage(context, success);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickQr() async {
    // Sin reducir ni comprimir: el servidor lo guarda en PNG sin pérdida para que se pueda escanear.
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null) {
      await _guard(() => ref.read(settingsApiProvider).uploadQr(file.path), 'QR actualizado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('QR de cobro', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text(
        'Genera el QR de cobro de tu cuenta en la app o banca de tu banco, guárdalo como imagen y súbelo '
        'aquí. Al cobrar con QR la app lo muestra con el monto a pagar.',
        style: TextStyle(color: AppColors.grey),
      ),
      const SizedBox(height: 12),
      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            if (settings.hasQr)
              SizedBox(
                height: 220,
                child: Image.network(settings.qrUrlVersioned!, fit: BoxFit.contain, filterQuality: FilterQuality.none,
                    errorBuilder: (_, _, _) => const Center(child: Text('No se pudo cargar el QR.'))),
              )
            else
              const Padding(padding: EdgeInsets.all(24), child: Text('Todavía no hay un QR cargado.')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('settings.uploadQr'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : _pickQr,
              icon: const Icon(Icons.qr_code_2),
              label: Text(settings.hasQr ? 'Cambiar QR' : 'Subir QR'),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Text('Datos de la cuenta', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(key: const Key('settings.bank'), controller: _bank, maxLength: 80, decoration: const InputDecoration(labelText: 'Banco')),
      TextField(controller: _holder, maxLength: 120, decoration: const InputDecoration(labelText: 'Titular')),
      TextField(controller: _account, maxLength: 40, decoration: const InputDecoration(labelText: 'N.º de cuenta (opcional)')),
      const SizedBox(height: 8),
      FilledButton(
        key: const Key('settings.save'),
        onPressed: _busy
            ? null
            : () => _guard(
                  () => ref.read(settingsApiProvider).updatePaymentSettings({
                    'bank_name': _bank.text.trim(),
                    'account_holder': _holder.text.trim(),
                    'account_number': _account.text.trim(),
                  }),
                  'Datos guardados.',
                ),
        child: const Text('Guardar datos'),
      ),
    ]);
  }
}
