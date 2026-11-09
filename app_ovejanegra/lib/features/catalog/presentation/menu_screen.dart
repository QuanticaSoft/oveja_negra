import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../auth/presentation/session_controller.dart';
import '../../orders/presentation/product_grid.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';

/// Cartilla por categoría. Con `products.availability` (ADMIN y CAJERO) se marca "agotado hoy".
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canToggle = ref.watch(sessionControllerProvider).value?.can('products.availability') ?? false;
    return AsyncView(
      value: ref.watch(menuProvider),
      onRetry: () => ref.invalidate(menuProvider),
      builder: (sections) => RefreshIndicator(
        onRefresh: () => ref.refresh(menuProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final section in sections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text(section.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              for (final product in section.products) _MenuItem(product: product, canToggle: canToggle),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends ConsumerWidget {
  const _MenuItem({required this.product, required this.canToggle});

  final Product product;
  final bool canToggle;

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool available) async {
    try {
      await ref.read(catalogApiProvider).setAvailability(product.id, available);
      refreshCatalog(ref);
    } on ApiException catch (e) {
      if (context.mounted) {
        showMessage(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: ProductImage(url: product.thumbUrl, size: 56),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([Money.bob(product.priceCents), if (product.description != null) product.description!].join(' · '),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: canToggle
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Switch(
                  key: Key('menu.available.${product.id}'),
                  value: product.isAvailable,
                  activeThumbColor: AppColors.orange,
                  onChanged: (v) => _toggle(context, ref, v),
                ),
                Text(product.isAvailable ? 'Disponible' : 'Agotado', style: const TextStyle(fontSize: 11)),
              ])
            : product.isAvailable
                ? null
                : const Text('AGOTADO', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}
