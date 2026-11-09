import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../orders/presentation/product_grid.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';

/// Administración del catálogo (`catalog.manage`): productos y categorías.
class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Productos'), Tab(text: 'Categorías')]),
        Expanded(child: TabBarView(children: [_ProductsTab(), _CategoriesTab()])),
      ]),
    );
  }
}

class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab();

  @override
  ConsumerState<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<_ProductsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('products.new'),
        onPressed: () => context.go('/products/new'),
        icon: const Icon(Icons.add),
        label: const Text('Producto'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre o descripción'),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: AsyncView(
            value: ref.watch(productsProvider(_query)),
            onRetry: () => ref.invalidate(productsProvider(_query)),
            builder: (products) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
              itemCount: products.length,
              itemBuilder: (_, i) {
                final p = products[i];
                return Card(
                  child: ListTile(
                    leading: ProductImage(url: p.thumbUrl, size: 48),
                    title: Text(p.name, style: TextStyle(decoration: p.isActive ? null : TextDecoration.lineThrough)),
                    subtitle: Text('${p.categoryName} · ${Money.bob(p.priceCents)}'
                        '${p.isActive ? '' : ' · desactivado'}${p.isAvailable ? '' : ' · agotado'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/products/${p.id}'),
                  ),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, [Category? category]) async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => _CategoryDialog(category: category),
    );
    if (result == null) {
      return;
    }
    final api = ref.read(catalogApiProvider);
    try {
      if (category == null) {
        await api.createCategory(result.$1, result.$2);
      } else {
        await api.updateCategory(category.id, {'name': result.$1, 'sort_order': result.$2});
      }
      refreshCatalog(ref);
    } on ApiException catch (e) {
      if (context.mounted) {
        showMessage(context, e.message);
      }
    }
  }

  Future<void> _setActive(BuildContext context, WidgetRef ref, Category category, bool active) async {
    try {
      await ref.read(catalogApiProvider).updateCategory(category.id, {'is_active': active});
      refreshCatalog(ref);
    } on ApiException catch (e) {
      if (context.mounted) {
        showMessage(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Categoría'),
      ),
      body: AsyncView(
        value: ref.watch(categoriesProvider),
        onRetry: () => ref.invalidate(categoriesProvider),
        builder: (categories) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            const Text('Las categorías desactivadas no aparecen en la cartilla. Nada se borra.', style: TextStyle(color: AppColors.grey)),
            for (final c in categories)
              Card(
                child: ListTile(
                  title: Text(c.name),
                  subtitle: Text('Orden ${c.sortOrder}'),
                  onTap: () => _edit(context, ref, c),
                  trailing: Switch(
                    value: c.isActive,
                    activeThumbColor: AppColors.orange,
                    onChanged: (v) => _setActive(context, ref, c, v),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category});

  final Category? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.name);
  late final _order = TextEditingController(text: '${widget.category?.sortOrder ?? 0}');

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'Nueva categoría' : 'Editar categoría'),
      content: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido.' : null,
          ),
          TextFormField(
            controller: _order,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Orden en la cartilla'),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < 0 || n > 10000 ? 'Entero entre 0 y 10000.' : null;
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, (_name.text.trim(), int.parse(_order.text)));
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
