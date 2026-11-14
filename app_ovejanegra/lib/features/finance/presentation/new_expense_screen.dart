import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/money_field.dart';
import '../../orders/domain/order.dart' show PaymentMethod;
import '../../reports/presentation/reports_providers.dart';
import 'expenses_screen.dart';

/// Registra un gasto operativo: un EGRESO en su fecha (no futura).
class NewExpenseScreen extends ConsumerStatefulWidget {
  const NewExpenseScreen({super.key});

  @override
  ConsumerState<NewExpenseScreen> createState() => _NewExpenseScreenState();
}

class _NewExpenseScreenState extends ConsumerState<NewExpenseScreen> {
  final _form = GlobalKey<FormState>();
  final _operation = IdempotentOperation();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  // La jornada (corte 04:00), igual que las ventas: así aparece en los reportes de "Hoy".
  DateTime _date = DayRange.today();
  int? _categoryId;
  PaymentMethod _method = PaymentMethod.efectivo;
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    final body = {
      'expense_date': DateFormat('yyyy-MM-dd').format(_date),
      'category_id': _categoryId,
      'description': _description.text.trim(),
      'amount': Money.toApi(Money.parseInput(_amount.text)!),
      'payment_method': _method.api,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(financeApiProvider).createExpense(body, _operation.keyFor(body));
      _operation.done();
      ref.invalidate(expensesProvider);
      if (mounted) {
        context.go('/expenses');
      }
    } on ApiException catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Nuevo gasto', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (error != null) ...[ErrorBanner(error.message), const SizedBox(height: 12)],
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2026), lastDate: DayRange.calendarToday());
            if (picked != null) {
              setState(() => _date = picked);
            }
          },
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text('Fecha: ${DateFormat('dd/MM/yyyy').format(_date)}'),
        ),
        const SizedBox(height: 12),
        AsyncView(
          value: ref.watch(expenseCategoriesProvider),
          onRetry: () => ref.invalidate(expenseCategoriesProvider),
          builder: (categories) => DropdownButtonFormField<int>(
            key: const Key('expense.category'),
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [for (final c in categories) if (c.isActive) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => _categoryId = v),
            validator: (v) => v == null ? 'Elige una categoría.' : null,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('expense.description'),
          controller: _description,
          maxLength: 300,
          decoration: InputDecoration(labelText: 'Descripción', errorText: error?.fieldError('description')),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerida.' : null,
        ),
        MoneyField(key: const Key('expense.amount'), controller: _amount, label: 'Importe', allowZero: false),
        const SizedBox(height: 12),
        SegmentedButton<PaymentMethod>(
          segments: [for (final m in PaymentMethod.values) ButtonSegment(value: m, label: Text(m.label))],
          selected: {_method},
          onSelectionChanged: (s) => setState(() => _method = s.first),
        ),
        const SizedBox(height: 20),
        FilledButton(key: const Key('expense.save'), onPressed: _saving ? null : _save, child: const Text('Registrar gasto')),
      ]),
    );
  }
}
