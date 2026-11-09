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
import '../../reports/presentation/reports_providers.dart';
import '../domain/finance.dart';

final expensesProvider =
    FutureProvider.autoDispose.family<List<Expense>, String?>((ref, status) => ref.watch(financeApiProvider).expenses(status: status));

final expenseCategoriesProvider =
    FutureProvider.autoDispose<List<ExpenseCategory>>((ref) => ref.watch(financeApiProvider).categories());

/// Gastos de los últimos 30 días y, con `expense_categories.manage` (ADMIN), sus categorías.
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCategories = ref.watch(sessionControllerProvider).value?.can('expense_categories.manage') ?? false;
    if (!canCategories) {
      return const _ExpensesTab();
    }
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Gastos'), Tab(text: 'Categorías')]),
        Expanded(child: TabBarView(children: [_ExpensesTab(), _CategoriesTab()])),
      ]),
    );
  }
}

class _ExpensesTab extends ConsumerStatefulWidget {
  const _ExpensesTab();

  @override
  ConsumerState<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends ConsumerState<_ExpensesTab> {
  String? _status;

  Future<void> _void(Expense expense) async {
    final reason = await askReason(context, title: 'Anular gasto de ${Money.bob(expense.amountCents)}', action: 'Anular gasto');
    if (reason == null) {
      return;
    }
    try {
      await ref.read(financeApiProvider).voidExpense(expense.id, reason);
      ref.invalidate(expensesProvider);
      if (mounted) {
        showMessage(context, 'Gasto anulado: el egreso se revirtió en su fecha.');
      }
    } on ApiException catch (e) {
      if (mounted) {
        showMessage(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).value!;
    return Scaffold(
      floatingActionButton: user.can('expenses.create')
          ? FloatingActionButton.extended(
              key: const Key('expenses.new'),
              onPressed: () => context.go('/expenses/new'),
              icon: const Icon(Icons.add),
              label: const Text('Gasto'),
            )
          : null,
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final (value, label) in [(null, 'Todos'), ('CONFIRMADO', 'Confirmados'), ('ANULADO', 'Anulados')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(label), selected: _status == value, onSelected: (_) => setState(() => _status = value)),
              ),
          ]),
        ),
        Expanded(
          child: AsyncView(
            value: ref.watch(expensesProvider(_status)),
            onRetry: () => ref.invalidate(expensesProvider(_status)),
            builder: (list) => RefreshIndicator(
              onRefresh: () => ref.refresh(expensesProvider(_status).future),
              child: list.isEmpty
                  ? ListView(children: const [SizedBox(height: 100), Center(child: Text('Sin gastos en los últimos 30 días.'))])
                  : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 88), children: [
                      for (final e in list)
                        Card(
                          child: ListTile(
                            title: Text('${e.categoryName} · ${e.description}',
                                style: TextStyle(decoration: e.isVoided ? TextDecoration.lineThrough : null)),
                            subtitle: Text(e.isVoided
                                ? 'ANULADO: ${e.voidReason}'
                                : '${LaPaz.date(e.date)} · ${e.method.label} · ${e.createdBy}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(Money.bob(e.amountCents), style: const TextStyle(fontWeight: FontWeight.w800)),
                              if (!e.isVoided && user.can('expenses.void'))
                                IconButton(
                                  key: Key('expense.void.${e.id}'),
                                  tooltip: 'Anular',
                                  icon: const Icon(Icons.cancel_outlined),
                                  onPressed: () => _void(e),
                                ),
                            ]),
                          ),
                        ),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, [ExpenseCategory? category]) async {
    final controller = TextEditingController(text: category?.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null ? 'Nueva categoría de gasto' : 'Renombrar categoría'),
        content: TextField(controller: controller, autofocus: true, maxLength: 60, decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) {
      return;
    }
    await _call(context, ref, () => category == null
        ? ref.read(financeApiProvider).createCategory(name)
        : ref.read(financeApiProvider).updateCategory(category.id, {'name': name}));
  }

  Future<void> _call(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(expenseCategoriesProvider);
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
        value: ref.watch(expenseCategoriesProvider),
        onRetry: () => ref.invalidate(expenseCategoriesProvider),
        builder: (list) => ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
          for (final c in list)
            Card(
              child: ListTile(
                title: Text(c.name),
                onTap: () => _edit(context, ref, c),
                trailing: Switch(
                  value: c.isActive,
                  activeThumbColor: AppColors.orange,
                  onChanged: (v) => _call(context, ref, () => ref.read(financeApiProvider).updateCategory(c.id, {'is_active': v})),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
