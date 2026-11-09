import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/quantity.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../auth/presentation/session_controller.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../domain/purchasing.dart';
import 'purchasing_providers.dart';

class PurchaseDetailScreen extends ConsumerStatefulWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final int purchaseId;

  @override
  ConsumerState<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends ConsumerState<PurchaseDetailScreen> {
  String? _error;

  Future<void> _void(Purchase purchase) async {
    final reason = await askReason(context, title: 'Anular compra', action: 'Anular compra');
    if (reason == null) {
      return;
    }
    setState(() => _error = null);
    try {
      await ref.read(purchasingApiProvider).voidPurchase(purchase.id, reason);
      ref
        ..invalidate(purchaseProvider(purchase.id))
        ..invalidate(purchasesProvider);
      refreshInventory(ref);
      if (mounted) {
        showMessage(context, 'Compra anulada: se devolvió el stock y se revirtió el egreso.');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.code == 'INSUFFICIENT_STOCK'
          ? '${inventoryErrorMessage(e)}\nParte de lo comprado ya se usó: registra antes un ajuste de inventario.'
          : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canVoid = ref.watch(sessionControllerProvider).value?.can('purchases.void') ?? false;
    return AsyncView(
      value: ref.watch(purchaseProvider(widget.purchaseId)),
      onRetry: () => ref.invalidate(purchaseProvider(widget.purchaseId)),
      builder: (p) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Compra del ${LaPaz.date(p.purchaseDate)}', style: Theme.of(context).textTheme.headlineSmall),
        Text([
          p.supplierName ?? 'Sin proveedor',
          if (p.receiptNumber != null) 'Comprobante ${p.receiptNumber}',
          p.paymentMethod.label,
          'Registró ${p.createdBy}',
        ].join(' · '), style: const TextStyle(color: AppColors.grey)),
        if (p.isVoided)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('ANULADA: ${p.voidReason}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              for (final i in p.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(i.ingredientName),
                  subtitle: Text('${Quantity.format(i.quantityMilli, i.unit)} × ${Money.bob(i.unitPriceCents)}'),
                  trailing: Text(Money.bob(i.lineCents)),
                ),
              const Divider(),
              Row(children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                Text(Money.bob(p.totalCents), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ]),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
        if (canVoid && !p.isVoided) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            key: const Key('purchase.void'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => _void(p),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Anular compra'),
          ),
        ],
      ]),
    );
  }
}
