import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/money.dart';
import '../../catalog/domain/catalog.dart';

/// Cartilla para vender: chips por categoría y tarjetas grandes, fáciles de tocar.
class ProductGrid extends StatefulWidget {
  const ProductGrid({super.key, required this.sections, required this.quantityOf, required this.onAdd, this.rejected = const {}});

  final List<MenuSection> sections;
  final int Function(int productId) quantityOf;
  final ValueChanged<Product> onAdd;

  /// Productos que el servidor rechazó por agotados (aunque la cartilla cargada diga disponibles).
  final Set<int> rejected;

  @override
  State<ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<ProductGrid> {
  int? _sectionId;

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    if (sections.isEmpty) {
      return const Center(child: Text('La cartilla no tiene productos activos.'));
    }
    final selected = sections.where((s) => s.id == _sectionId).firstOrNull;
    final products = selected?.products ?? [for (final s in sections) ...s.products];
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _chip('Todo', selected == null, () => setState(() => _sectionId = null)),
              for (final s in sections) _chip(s.name, s.id == _sectionId, () => setState(() => _sectionId = s.id)),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) {
              final product = products[i];
              return ProductCard(
                product: product,
                quantity: widget.quantityOf(product.id),
                available: product.isAvailable && !widget.rejected.contains(product.id),
                onTap: () => widget.onAdd(product),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.quantity, required this.available, required this.onTap});

  final Product product;
  final int quantity;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('product.${product.id}'),
        onTap: available ? onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                ProductImage(url: product.thumbUrl),
                if (quantity > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.orange,
                      child: Text('$quantity', style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.w800)),
                    ),
                  ),
                if (!available)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: const Text('AGOTADO', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w800)),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(Money.bob(product.priceCents), style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
      ),
    );
    return available ? card : Opacity(opacity: 0.6, child: card);
  }
}

/// Foto del producto o un ícono si no tiene (o si no carga).
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.url, this.size});

  final String? url;
  final double? size;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: Color(0xFFEFEFEF),
      child: Center(child: Icon(Icons.lunch_dining, color: AppColors.grey, size: 36)),
    );
    final image = url == null
        ? placeholder
        : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
    return size == null ? image : SizedBox.square(dimension: size, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: image));
  }
}
