import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/quantity.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/money_field.dart';
import '../../../core/widgets/quantity_field.dart';
import '../../inventory/domain/inventory.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../orders/domain/order.dart' show PaymentMethod;
import '../domain/purchasing.dart';
import 'purchasing_providers.dart';

class _Line {
  _Line(this.ingredient);

  final Ingredient ingredient;
  final quantity = TextEditingController();
  final price = TextEditingController();

  PurchaseLineDraft? draft() {
    final milli = Quantity.parseInput(quantity.text);
    final cents = Money.parseInput(price.text);
    if (milli == null || milli == 0 || cents == null) {
      return null;
    }
    return PurchaseLineDraft(
      ingredientId: ingredient.id,
      ingredientName: ingredient.name,
      unit: ingredient.unit.code,
      quantityMilli: milli,
      unitPriceCents: cents,
    );
  }

  void dispose() {
    quantity.dispose();
    price.dispose();
  }
}

/// Registra una compra: suma stock, recalcula el costo promedio y genera el egreso en su fecha.
class NewPurchaseScreen extends ConsumerStatefulWidget {
  const NewPurchaseScreen({super.key});

  @override
  ConsumerState<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends ConsumerState<NewPurchaseScreen> {
  final _form = GlobalKey<FormState>();
  final _operation = IdempotentOperation();
  final _lines = <_Line>[];
  final _receipt = TextEditingController();
  // La jornada (corte 04:00), igual que las ventas: así aparece en los reportes de "Hoy".
  DateTime _date = DayRange.today();
  int? _supplierId;
  PaymentMethod _method = PaymentMethod.efectivo;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _receipt.dispose();
    super.dispose();
  }

  int get _totalCents => _lines.fold(0, (sum, l) => sum + (l.draft()?.lineCents ?? 0));

  Future<void> _addLine() async {
    final picked = await pickIngredient(context, exclude: {for (final l in _lines) l.ingredient.id});
    if (picked != null) {
      setState(() => _lines.add(_Line(picked)));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2026), lastDate: DayRange.calendarToday());
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save() async {
    if (_lines.isEmpty || !_form.currentState!.validate()) {
      return;
    }
    if (_totalCents == 0) {
      setState(() => _error = 'El total de la compra debe ser mayor que 0.');
      return;
    }
    final body = {
      'purchase_date': DateFormat('yyyy-MM-dd').format(_date),
      'supplier_id': _supplierId,
      if (_receipt.text.trim().isNotEmpty) 'receipt_number': _receipt.text.trim(),
      'payment_method': _method.api,
      'items': [for (final l in _lines) l.draft()!.toApi()],
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final purchase = await ref.read(purchasingApiProvider).create(body, _operation.keyFor(body));
      _operation.done();
      ref.invalidate(purchasesProvider);
      refreshInventory(ref);
      if (mounted) {
        context.go('/purchases/${purchase.id}');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.code == 'INGREDIENT_INACTIVE' ? inventoryErrorMessage(e) : e.message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Nueva compra', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text('Fecha de la boleta: ${DateFormat('dd/MM/yyyy').format(_date)}'),
          ),
          SegmentedButton<PaymentMethod>(
            segments: [for (final m in PaymentMethod.values) ButtonSegment(value: m, label: Text(m.label))],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
        ]),
        const SizedBox(height: 12),
        AsyncView(
          value: ref.watch(suppliersProvider),
          onRetry: () => ref.invalidate(suppliersProvider),
          builder: (suppliers) => DropdownButtonFormField<int?>(
            initialValue: _supplierId,
            decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Sin proveedor')),
              for (final s in suppliers)
                if (s.isActive) DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _supplierId = v),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(controller: _receipt, maxLength: 40, decoration: const InputDecoration(labelText: 'N.º de comprobante (opcional)')),
        Text('Insumos', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (index, line) in _lines.indexed) _lineCard(index, line),
        OutlinedButton.icon(
          key: const Key('purchase.addLine'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _addLine,
          icon: const Icon(Icons.add),
          label: const Text('Agregar insumo'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Text('Total', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          Text(Money.bob(_totalCents), key: const Key('purchase.total'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
        FilledButton(
          key: const Key('purchase.save'),
          onPressed: _saving || _lines.isEmpty ? null : _save,
          child: const Text('Registrar compra'),
        ),
      ]),
    );
  }

  Widget _lineCard(int index, _Line line) {
    final draft = line.draft();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(line.ingredient.name, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (draft != null) Text(Money.bob(draft.lineCents), style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.removeAt(index).dispose())),
          ]),
          Row(children: [
            Expanded(
              child: QuantityField(
                key: Key('purchase.quantity.$index'),
                controller: line.quantity,
                label: 'Cantidad',
                unit: line.ingredient.unit.code,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MoneyField(
                key: Key('purchase.price.$index'),
                controller: line.price,
                label: 'Precio por ${line.ingredient.unit.code}',
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
