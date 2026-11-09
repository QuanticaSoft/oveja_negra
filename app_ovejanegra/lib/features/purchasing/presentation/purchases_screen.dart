import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/purchasing.dart';
import 'purchasing_providers.dart';

/// Compras (últimos 30 días) y, con `suppliers.manage`, proveedores.
class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSuppliers = ref.watch(sessionControllerProvider).value?.can('suppliers.manage') ?? false;
    if (!canSuppliers) {
      return const _PurchasesTab();
    }
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Compras'), Tab(text: 'Proveedores')]),
        Expanded(child: TabBarView(children: [_PurchasesTab(), _SuppliersTab()])),
      ]),
    );
  }
}

class _PurchasesTab extends ConsumerStatefulWidget {
  const _PurchasesTab();

  @override
  ConsumerState<_PurchasesTab> createState() => _PurchasesTabState();
}

class _PurchasesTabState extends ConsumerState<_PurchasesTab> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(sessionControllerProvider).value?.can('purchases.create') ?? false;
    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              key: const Key('purchases.new'),
              onPressed: () => context.go('/purchases/new'),
              icon: const Icon(Icons.add),
              label: const Text('Compra'),
            )
          : null,
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final (value, label) in [(null, 'Todas'), ('CONFIRMADA', 'Confirmadas'), ('ANULADA', 'Anuladas')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(label), selected: _status == value, onSelected: (_) => setState(() => _status = value)),
              ),
          ]),
        ),
        Expanded(
          child: AsyncView(
            value: ref.watch(purchasesProvider(_status)),
            onRetry: () => ref.invalidate(purchasesProvider(_status)),
            builder: (list) => RefreshIndicator(
              onRefresh: () => ref.refresh(purchasesProvider(_status).future),
              child: list.isEmpty
                  ? ListView(children: const [SizedBox(height: 100), Center(child: Text('Sin compras en los últimos 30 días.'))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _PurchaseCard(purchase: list[i]),
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({required this.purchase});

  final Purchase purchase;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    return Card(
      child: ListTile(
        key: Key('purchase.${p.id}'),
        onTap: () => context.go('/purchases/${p.id}'),
        title: Text('${LaPaz.date(p.purchaseDate)} · ${p.supplierName ?? 'Sin proveedor'}',
            style: TextStyle(fontWeight: FontWeight.w700, decoration: p.isVoided ? TextDecoration.lineThrough : null)),
        subtitle: Text(p.items.map((i) => i.ingredientName).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Money.bob(p.totalCents), style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(p.isVoided ? 'ANULADA' : p.paymentMethod.label, style: const TextStyle(fontSize: 12, color: AppColors.grey)),
        ]),
      ),
    );
  }
}

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, [Supplier? supplier]) async {
    final fields = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _SupplierDialog(supplier: supplier));
    if (fields == null) {
      return;
    }
    final api = ref.read(purchasingApiProvider);
    try {
      supplier == null ? await api.createSupplier(fields) : await api.updateSupplier(supplier.id, fields);
      ref.invalidate(suppliersProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        showMessage(context, e.fieldError('phone') ?? e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Proveedor'),
      ),
      body: AsyncView(
        value: ref.watch(suppliersProvider),
        onRetry: () => ref.invalidate(suppliersProvider),
        builder: (list) => ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
          for (final s in list)
            Card(
              child: ListTile(
                title: Text(s.name, style: TextStyle(decoration: s.isActive ? null : TextDecoration.lineThrough)),
                subtitle: Text([s.phone, s.notes].whereType<String>().join(' · ')),
                onTap: () => _edit(context, ref, s),
                trailing: Switch(
                  value: s.isActive,
                  activeThumbColor: AppColors.orange,
                  onChanged: (v) async {
                    try {
                      await ref.read(purchasingApiProvider).updateSupplier(s.id, {'is_active': v});
                      ref.invalidate(suppliersProvider);
                    } on ApiException catch (e) {
                      if (context.mounted) {
                        showMessage(context, e.message);
                      }
                    }
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({this.supplier});

  final Supplier? supplier;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name);
  late final _phone = TextEditingController(text: widget.supplier?.phone);
  late final _notes = TextEditingController(text: widget.supplier?.notes);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.supplier == null ? 'Nuevo proveedor' : 'Editar proveedor'),
        content: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido.' : null,
            ),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
            const SizedBox(height: 8),
            TextFormField(controller: _notes, maxLength: 500, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, {
                  'name': _name.text.trim(),
                  'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                  'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                });
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      );
}
