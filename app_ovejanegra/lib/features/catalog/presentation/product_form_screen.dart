import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/money_field.dart';
import '../../orders/presentation/product_grid.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';

/// Alta (`productId` null) o edición de un producto.
class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({super.key, this.productId});

  final int? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    if (productId == null) {
      return AsyncView(
        value: categories,
        onRetry: () => ref.invalidate(categoriesProvider),
        builder: (cats) => _ProductForm(categories: cats),
      );
    }
    final product = ref.watch(productProvider(productId!));
    return AsyncView(
      value: product,
      onRetry: () => ref.invalidate(productProvider(productId!)),
      builder: (p) => AsyncView(
        value: categories,
        onRetry: () => ref.invalidate(categoriesProvider),
        builder: (cats) => _ProductForm(categories: cats, product: p),
      ),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({required this.categories, this.product});

  final List<Category> categories;
  final Product? product;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _description = TextEditingController(text: widget.product?.description);
  final _price = TextEditingController();
  late int? _categoryId = widget.product?.categoryId;
  bool _busy = false;
  ApiException? _error;

  bool get _isNew => widget.product == null;

  @override
  void dispose() {
    for (final c in [_name, _description, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    final api = ref.read(catalogApiProvider);
    final description = _description.text.trim().isEmpty ? null : _description.text.trim();
    await _guard(() async {
      if (_isNew) {
        final created = await api.createProduct(
          categoryId: _categoryId!,
          name: _name.text.trim(),
          description: description,
          priceCents: Money.parseInput(_price.text)!,
        );
        refreshCatalog(ref);
        if (mounted) {
          // A la edición, para poder agregarle la foto.
          context.go('/products/${created.id}');
        }
      } else {
        await api.updateProduct(widget.product!.id, {'name': _name.text.trim(), 'category_id': _categoryId, 'description': description});
        refreshCatalog(ref);
        if (mounted) {
          showMessage(context, 'Producto guardado.');
        }
      }
    });
  }

  Future<void> _changePrice() async {
    final controller = TextEditingController(text: Money.toApi(widget.product!.priceCents).replaceAll('.', ','));
    final form = GlobalKey<FormState>();
    final cents = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar precio'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Queda en el historial. Los pedidos ya registrados conservan su precio.'),
            const SizedBox(height: 12),
            MoneyField(controller: controller, label: 'Precio nuevo', allowZero: false, autofocus: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, Money.parseInput(controller.text));
              }
            },
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
    if (cents != null) {
      await _guard(() async {
        await ref.read(catalogApiProvider).changePrice(widget.product!.id, cents);
        refreshCatalog(ref);
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    // 1600 px y calidad 85: la subida pesa poco; el servidor igual re-codifica a 800 px.
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (file == null) {
      return;
    }
    await _guard(() async {
      await ref.read(catalogApiProvider).uploadImage(widget.product!.id, file.path);
      refreshCatalog(ref);
      if (mounted) {
        showMessage(context, 'Foto actualizada.');
      }
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final activeCategories = [for (final c in widget.categories) if (c.isActive || c.id == _categoryId) c];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_isNew ? 'Nuevo producto' : product!.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (product != null) ...[
          Row(children: [
            ProductImage(url: product.thumbUrl, size: 96),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galería'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Cámara'),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
        ],
        if (_error != null) ...[ErrorBanner(_error!.message), const SizedBox(height: 12)],
        Form(
          key: _form,
          child: Column(children: [
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [for (final c in activeCategories) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _categoryId = v),
              validator: (v) => v == null ? 'Elige una categoría.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('product.name'),
              controller: _name,
              maxLength: 80,
              decoration: InputDecoration(labelText: 'Nombre', errorText: _error?.fieldError('name')),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido.' : null,
            ),
            TextFormField(
              controller: _description,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
            ),
            if (_isNew) ...[
              const SizedBox(height: 4),
              MoneyField(key: const Key('product.price'), controller: _price, label: 'Precio', allowZero: false),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton(key: const Key('product.save'), onPressed: _busy ? null : _save, child: Text(_isNew ? 'Crear producto' : 'Guardar')),
        if (product != null) ...[
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              title: Text('Precio: ${Money.bob(product.priceCents)}', style: const TextStyle(fontWeight: FontWeight.w800)),
              trailing: TextButton(onPressed: _busy ? null : _changePrice, child: const Text('Cambiar')),
            ),
          ),
          Card(
            child: SwitchListTile(
              title: const Text('Activo'),
              subtitle: const Text('Desactivado no aparece en la cartilla. Nunca se borra.'),
              activeThumbColor: AppColors.orange,
              value: product.isActive,
              onChanged: _busy
                  ? null
                  : (v) => _guard(() async {
                        await ref.read(catalogApiProvider).setActive(product.id, v);
                        refreshCatalog(ref);
                      }),
            ),
          ),
          const SizedBox(height: 12),
          Text('Historial de precios', style: Theme.of(context).textTheme.titleMedium),
          AsyncView(
            value: ref.watch(priceHistoryProvider(product.id)),
            onRetry: () => ref.invalidate(priceHistoryProvider(product.id)),
            builder: (history) => history.isEmpty
                ? const Padding(padding: EdgeInsets.all(8), child: Text('Sin cambios de precio.'))
                : Column(children: [
                    for (final h in history)
                      ListTile(
                        dense: true,
                        title: Text('${Money.bob(h.oldCents)} → ${Money.bob(h.newCents)}'),
                        subtitle: Text('${LaPaz.dateTime(h.changedAt)} · ${h.changedBy}'),
                      ),
                  ]),
          ),
        ],
      ],
    );
  }
}
