<?php

declare(strict_types=1);

/** Kardex, ajustes y salidas manuales por consumo (hasta que existan recetas, Etapa 2). */
final class InventoryService
{
    public const MOVEMENT_TYPES = ['ENTRADA_COMPRA', 'SALIDA_CONSUMO', 'AJUSTE', 'REVERSO'];
    private const MAX_CONSUMPTION_LINES = 50;
    private const REASON_ERROR = 'Requerido, máximo 300 caracteres.';

    private readonly InventoryLedger $ledger;

    public function __construct(
        private readonly PDO $db,
        private readonly AuthUser $actor,
        private readonly string $dayCutoff = '04:00',
    ) {
        $this->ledger = new InventoryLedger($db);
    }

    /** @return array{data: list<array>, meta: array} */
    public function movements(array $query): array
    {
        $today = (string) $this->scalar('SELECT business_date_of(now(), ?::interval)::text', [$this->dayCutoff]);
        $range = DateRange::fromQuery($query, (new DateTimeImmutable($today))->modify('-29 days')->format('Y-m-d'), $today);
        // Rango de días operativos convertido a timestamps, para que use el índice de created_at.
        $where = ["m.created_at >= (?::date + ?::interval) AT TIME ZONE 'America/La_Paz'",
                  "m.created_at < (?::date + 1 + ?::interval) AT TIME ZONE 'America/La_Paz'"];
        $params = [$range->from, $this->dayCutoff, $range->to, $this->dayCutoff];
        if (isset($query['ingredient_id'])) {
            $where[] = 'm.ingredient_id = ?';
            $params[] = Validation::positiveInt($query['ingredient_id'])
                ?? throw ApiException::validation(['ingredient_id' => 'Entero positivo.']);
        }
        if (isset($query['type'])) {
            if (!in_array($query['type'], self::MOVEMENT_TYPES, true)) {
                throw ApiException::validation(['type' => 'Uno de: ' . implode(', ', self::MOVEMENT_TYPES) . '.']);
            }
            $where[] = 'm.type = ?';
            $params[] = $query['type'];
        }
        $pagination = Pagination::fromQuery($query);
        $whereSql = ' WHERE ' . implode(' AND ', $where);

        $total = (int) $this->scalar('SELECT count(*) FROM inventory_movements m' . $whereSql, $params);
        $stmt = $this->db->prepare(
            'SELECT m.*, i.name AS ingredient_name, u.code AS unit_code, cu.full_name AS created_by_name
             FROM inventory_movements m
             JOIN ingredients i ON i.id = m.ingredient_id
             JOIN units u ON u.id = i.unit_id
             JOIN users cu ON cu.id = m.created_by' . $whereSql . '
             ORDER BY m.id DESC LIMIT ? OFFSET ?'
        );
        $stmt->execute([...$params, $pagination->perPage, $pagination->offset()]);
        return ['data' => array_map(self::movementToPublic(...), $stmt->fetchAll()), 'meta' => $pagination->meta($total)];
    }

    /** Ajuste con signo (conteo físico, merma, hallazgo). No cambia el costo promedio. */
    public function adjust(array $input): array
    {
        $errors = [];
        $ingredientId = Validation::positiveInt($input['ingredient_id'] ?? null);
        if ($ingredientId === null) {
            $errors['ingredient_id'] = 'Requerido.';
        }
        $quantity = Validation::quantity($input['quantity'] ?? null, signed: true);
        if ($quantity === null) {
            $errors['quantity'] = 'Cantidad distinta de 0 (positiva o negativa) con hasta 3 decimales.';
        }
        $reason = Validation::text($input['reason'] ?? null, 300);
        if ($reason === null) {
            $errors['reason'] = self::REASON_ERROR;
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }

        return Db::transaction($this->db, function () use ($ingredientId, $quantity, $reason): array {
            $locked = $this->ledger->lockAndCheck([$ingredientId => $quantity]);
            if (!isset($locked[$ingredientId])) {
                throw ApiException::validation(['ingredient_id' => 'Insumo inexistente.']);
            }
            $id = $this->ledger->move($ingredientId, 'AJUSTE', $quantity, null, null, null, $reason, $this->actor->id);
            Audit::log($this->db, $this->actor->id, 'inventory_movements', $id, 'adjust', null,
                ['ingredient_id' => $ingredientId, 'quantity' => Quantity::fromMilli($quantity), 'reason' => $reason]);
            return $this->movement($id);
        });
    }

    /** Varias salidas por consumo en una transacción: o se registran todas o ninguna. */
    public function consume(array $input): array
    {
        $errors = [];
        $items = $input['items'] ?? null;
        $deltas = [];
        if (!is_array($items) || !array_is_list($items) || $items === [] || count($items) > self::MAX_CONSUMPTION_LINES) {
            $errors['items'] = 'Lista de 1 a ' . self::MAX_CONSUMPTION_LINES . ' insumos.';
        } else {
            foreach ($items as $index => $item) {
                $ingredientId = is_array($item) ? Validation::positiveInt($item['ingredient_id'] ?? null) : null;
                $quantity = is_array($item) ? Validation::quantity($item['quantity'] ?? null) : null;
                if ($ingredientId === null) {
                    $errors["items.{$index}.ingredient_id"] = 'Requerido.';
                } elseif (isset($deltas[$ingredientId])) {
                    $errors["items.{$index}.ingredient_id"] = 'Insumo repetido: suma la cantidad en una sola línea.';
                }
                if ($quantity === null) {
                    $errors["items.{$index}.quantity"] = 'Cantidad mayor que 0 con hasta 3 decimales.';
                }
                if ($ingredientId !== null && $quantity !== null) {
                    $deltas[$ingredientId] ??= -$quantity;
                }
            }
        }
        $reason = Validation::text($input['reason'] ?? null, 300);
        if ($reason === null) {
            $errors['reason'] = self::REASON_ERROR;
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }

        return Db::transaction($this->db, function () use ($deltas, $reason): array {
            $locked = $this->ledger->lockAndCheck($deltas);
            self::assertUsable($deltas, $locked);
            $ids = [];
            foreach ($deltas as $ingredientId => $delta) {
                $ids[] = $this->ledger->move($ingredientId, 'SALIDA_CONSUMO', $delta, null, null, null, $reason, $this->actor->id);
            }
            Audit::log($this->db, $this->actor->id, 'inventory_movements', $ids[0], 'consume', null,
                ['movement_ids' => $ids, 'reason' => $reason]);
            return array_map($this->movement(...), $ids);
        });
    }

    /**
     * Rechaza insumos inexistentes (400) o desactivados (409). Lo usan también las compras.
     *
     * @param array<int, int> $deltas
     * @param array<int, array> $locked
     */
    public static function assertUsable(array $deltas, array $locked, string $field = 'items'): void
    {
        $errors = [];
        $inactive = [];
        $index = 0;
        foreach (array_keys($deltas) as $ingredientId) {
            $ingredient = $locked[$ingredientId] ?? null;
            if ($ingredient === null) {
                $errors["{$field}.{$index}.ingredient_id"] = 'Insumo inexistente.';
            } elseif (!$ingredient['is_active']) {
                $inactive[] = ['id' => $ingredientId, 'name' => $ingredient['name']];
            }
            $index++;
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($inactive !== []) {
            throw new ApiException('INGREDIENT_INACTIVE', 'Hay insumos desactivados.', 409, ['ingredients' => $inactive]);
        }
    }

    private function movement(int $id): array
    {
        $stmt = $this->db->prepare(
            'SELECT m.*, i.name AS ingredient_name, u.code AS unit_code, cu.full_name AS created_by_name
             FROM inventory_movements m
             JOIN ingredients i ON i.id = m.ingredient_id
             JOIN units u ON u.id = i.unit_id
             JOIN users cu ON cu.id = m.created_by
             WHERE m.id = ?'
        );
        $stmt->execute([$id]);
        return self::movementToPublic($stmt->fetch());
    }

    private static function movementToPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'ingredient' => ['id' => (int) $row['ingredient_id'], 'name' => $row['ingredient_name'], 'unit' => $row['unit_code']],
            'type' => $row['type'],
            'quantity' => $row['quantity'],
            'unit_cost' => $row['unit_cost'],
            'stock_after' => $row['stock_after'],
            'source' => $row['source_type'] === null ? null : ['type' => $row['source_type'], 'id' => (int) $row['source_id']],
            'reason' => $row['reason'],
            'created_by' => ['id' => (int) $row['created_by'], 'full_name' => $row['created_by_name']],
            'created_at' => Dates::iso($row['created_at']),
        ];
    }

    private function scalar(string $sql, array $params): mixed
    {
        $stmt = $this->db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchColumn();
    }
}
