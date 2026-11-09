<?php

declare(strict_types=1);

/**
 * Único punto que escribe inventory_movements y actualiza ingredients.current_stock (su caché),
 * siempre juntos. Las recetas de la Etapa 2 también pasarán por aquí.
 */
final class InventoryLedger
{
    private readonly IngredientRepository $ingredients;

    public function __construct(private readonly PDO $db)
    {
        $this->ingredients = new IngredientRepository($db);
    }

    /**
     * Bloquea los insumos y verifica que ninguno quede con stock negativo.
     *
     * @param array<int, int> $deltas ingredient_id => milésimas con signo
     * @return array<int, array> insumos bloqueados por id
     * @throws ApiException 409 INSUFFICIENT_STOCK con el detalle de cada faltante
     */
    public function lockAndCheck(array $deltas): array
    {
        $locked = $this->ingredients->lockMany(array_keys($deltas));
        $missing = [];
        foreach ($deltas as $ingredientId => $delta) {
            $ingredient = $locked[$ingredientId] ?? null;
            if ($ingredient === null) {
                continue;
            }
            $stock = Quantity::toMilli($ingredient['current_stock']);
            if ($stock + $delta < 0) {
                $missing[] = [
                    'ingredient_id' => $ingredientId,
                    'name' => $ingredient['name'],
                    'unit' => $ingredient['unit_code'],
                    'stock' => $ingredient['current_stock'],
                    'required' => Quantity::fromMilli(-$delta),
                ];
            }
        }
        if ($missing !== []) {
            throw new ApiException('INSUFFICIENT_STOCK',
                'El stock no alcanza para esta operación.', 409,
                ['ingredients' => $missing]);
        }
        return $locked;
    }

    /**
     * Registra el movimiento sobre un insumo ya bloqueado. Con $unitCost (entrada de compra o su
     * reverso) recalcula el promedio ponderado: (stock·prom + q·c) / (stock + q), con q negativo en el
     * reverso. Si el stock queda en 0 se conserva el último costo.
     */
    public function move(
        int $ingredientId,
        string $type,
        int $deltaMilli,
        ?string $unitCost,
        ?string $sourceType,
        ?int $sourceId,
        ?string $reason,
        int $createdBy,
    ): int {
        $delta = Quantity::fromMilli($deltaMilli);
        $stmt = $this->db->prepare(
            'UPDATE ingredients SET
                 avg_unit_cost = CASE
                     WHEN ?::numeric IS NULL OR current_stock + ?::numeric = 0 THEN avg_unit_cost
                     ELSE GREATEST(0, round((current_stock * avg_unit_cost + ?::numeric * ?::numeric) / (current_stock + ?::numeric), 4))
                 END,
                 current_stock = current_stock + ?::numeric
             WHERE id = ?
             RETURNING current_stock'
        );
        $stmt->execute([$unitCost, $delta, $delta, $unitCost, $delta, $delta, $ingredientId]);
        $stockAfter = $stmt->fetchColumn();

        $insert = $this->db->prepare(
            'INSERT INTO inventory_movements
                 (ingredient_id, type, quantity, unit_cost, stock_after, source_type, source_id, reason, created_by)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id'
        );
        $insert->execute([$ingredientId, $type, $delta, $unitCost, $stockAfter, $sourceType, $sourceId, $reason, $createdBy]);
        return (int) $insert->fetchColumn();
    }
}
