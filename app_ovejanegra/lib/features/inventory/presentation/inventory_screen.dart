import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/utils/quantity.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/inventory.dart';
import 'inventory_providers.dart';
import 'inventory_widgets.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTabController(
        length: 2,
        child: Column(children: [
          TabBar(tabs: [Tab(text: 'Insumos'), Tab(text: 'Movimientos')]),
          Expanded(child: TabBarView(children: [_IngredientsTab(), _MovementsTab()])),
        ]),
      );
}

class _IngredientsTab extends ConsumerStatefulWidget {
  const _IngredientsTab();

  @override
  ConsumerState<_IngredientsTab> createState() => _IngredientsTabState();
}

class _IngredientsTabState extends ConsumerState<_IngredientsTab> {
  String _query = '';
  bool _lowOnly = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).value!;
    final query = (query: _query, lowStockOnly: _lowOnly);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar insumo'),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
          FilterChip(
            key: const Key('inventory.lowOnly'),
            label: const Text('Solo stock bajo'),
            selected: _lowOnly,
            onSelected: (v) => setState(() => _lowOnly = v),
          ),
          const SizedBox(width: 8),
          if (user.can('inventory.consume'))
            ActionChip(
              key: const Key('inventory.consume'),
              avatar: const Icon(Icons.restaurant_outlined, size: 18),
              label: const Text('Registrar consumo'),
              onPressed: () => context.go('/inventory/consume'),
            ),
          const SizedBox(width: 8),
          if (user.can('ingredients.manage'))
            ActionChip(
              key: const Key('inventory.new'),
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Nuevo insumo'),
              onPressed: () => context.go('/inventory/new'),
            ),
        ]),
      ),
      Expanded(
        child: AsyncView(
          value: ref.watch(ingredientsProvider(query)),
          onRetry: () => ref.invalidate(ingredientsProvider(query)),
          builder: (list) => RefreshIndicator(
            onRefresh: () => ref.refresh(ingredientsProvider(query).future),
            child: list.isEmpty
                ? ListView(children: const [SizedBox(height: 100), Center(child: Text('No hay insumos con este filtro.'))])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _IngredientCard(ingredient: list[i]),
                  ),
          ),
        ),
      ),
    ]);
  }
}

class _IngredientCard extends StatelessWidget {
  const _IngredientCard({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    final i = ingredient;
    return Card(
      child: ListTile(
        key: Key('ingredient.${i.id}'),
        onTap: () => context.go('/inventory/${i.id}'),
        title: Row(children: [
          Flexible(child: Text(i.name, style: TextStyle(fontWeight: FontWeight.w700, decoration: i.isActive ? null : TextDecoration.lineThrough))),
          if (i.isLowStock) ...[const SizedBox(width: 8), const LowStockBadge()],
        ]),
        subtitle: Text('${i.categoryName} · mínimo ${Quantity.format(i.minStockMilli, i.unit.code)} · prom. ${i.avgCostLabel}'),
        trailing: Text(i.stockLabel,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: i.isLowStock ? AppColors.orange : null)),
      ),
    );
  }
}

class _MovementsTab extends ConsumerStatefulWidget {
  const _MovementsTab();

  @override
  ConsumerState<_MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends ConsumerState<_MovementsTab> {
  MovementType? _type;

  @override
  Widget build(BuildContext context) {
    final query = (ingredientId: null, type: _type);
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: const Text('Todos'), selected: _type == null, onSelected: (_) => setState(() => _type = null)),
          ),
          for (final t in MovementType.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(t.label), selected: _type == t, onSelected: (_) => setState(() => _type = t)),
            ),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Align(alignment: Alignment.centerLeft, child: Text('Últimos 30 días', style: TextStyle(color: AppColors.grey))),
      ),
      Expanded(
        child: AsyncView(
          value: ref.watch(movementsProvider(query)),
          onRetry: () => ref.invalidate(movementsProvider(query)),
          builder: (list) => RefreshIndicator(
            onRefresh: () => ref.refresh(movementsProvider(query).future),
            child: list.isEmpty
                ? ListView(children: const [SizedBox(height: 100), Center(child: Text('Sin movimientos.'))])
                : ListView(children: [for (final m in list) MovementTile(movement: m, showIngredient: true)]),
          ),
        ),
      ),
    ]);
  }
}
