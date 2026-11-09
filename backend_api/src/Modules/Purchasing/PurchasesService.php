<?php

declare(strict_types=1);

/**
 * Compra confirmada = un EGRESO (en su fecha) + una ENTRADA_COMPRA por ítem, en la misma transacción.
 * No se edita: se anula (REVERSO por ítem + reverso del egreso en la misma fecha) y se registra otra.
 */
final class PurchasesService
{
    public const LEDGER_CATEGORY = 'COMPRA_INSUMOS';
    private const PAYMENT_METHODS = ['EFECTIVO', 'QR'];
    private const STATUSES = ['CONFIRMADA', 'ANULADA'];
    private const MAX_LINES = 100;
    // Con cantidad ≤ 99 999,999 y precio ≤ Bs 1 000 000 el producto en enteros nunca desborda.
    private const MAX_UNIT_PRICE_CENTS = 100_000_000;

    private readonly PurchaseRepository $purchases;
    private readonly SuppliersService $suppliers;
    private readonly InventoryLedger $inventory;
    private readonly FinanceLedger $finance;

    public function __construct(
        private readonly PDO $db,
        private readonly AuthUser $actor,
        private readonly string $dayCutoff = '04:00',
    ) {
        $this->purchases = new PurchaseRepository($db);
        $this->suppliers = new SuppliersService($db, $actor);
        $this->inventory = new InventoryLedger($db);
        $this->finance = new FinanceLedger($db, $dayCutoff);
    }

    /** @return array{data: list<array>, meta: array} por defecto, los últimos 30 días */
    public function list(array $query): array
    {
        $today = $this->today();
        $range = DateRange::fromQuery($query, (new DateTimeImmutable($today))->modify('-29 days')->format('Y-m-d'), $today);
        $supplierId = null;
        if (isset($query['supplier_id'])) {
            $supplierId = Validation::positiveInt($query['supplier_id'])
                ?? throw ApiException::validation(['supplier_id' => 'Entero positivo.']);
        }
        $status = $query['status'] ?? null;
        if ($status !== null && !in_array($status, self::STATUSES, true)) {
            throw ApiException::validation(['status' => 'CONFIRMADA o ANULADA.']);
        }
        $pagination = Pagination::fromQuery($query);
        $result = $this->purchases->list(
            ['from' => $range->from, 'to' => $range->to, 'supplier_id' => $supplierId, 'status' => $status],
            $pagination->perPage, $pagination->offset());
        $items = $this->purchases->itemsFor(array_map(static fn (array $row): int => (int) $row['id'], $result['rows']));
        return [
            'data' => array_map(static fn (array $row): array => self::toPublic($row, $items[(int) $row['id']] ?? []), $result['rows']),
            'meta' => $pagination->meta($result['total']),
        ];
    }

    public function get(int $id): array
    {
        return $this->detail($this->purchases->find($id) ?? throw self::notFound());
    }

    /** @return array{purchase: array, created: bool} created = false si es un reintento con la misma clave */
    public function create(array $input, ?string $idempotencyKey): array
    {
        $key = Idempotency::key($idempotencyKey);
        $errors = [];
        $purchaseDate = Validation::date($input['purchase_date'] ?? null);
        if ($purchaseDate === null) {
            $errors['purchase_date'] = 'Fecha YYYY-MM-DD.';
        } elseif ($purchaseDate > $this->today()) {
            $errors['purchase_date'] = 'No puede ser una fecha futura.';
        }
        $supplierId = null;
        if (($input['supplier_id'] ?? null) !== null) {
            $supplierId = Validation::positiveInt($input['supplier_id']);
            if ($supplierId === null) {
                $errors['supplier_id'] = 'Entero positivo o null.';
            }
        }
        $receiptNumber = Validation::optionalText($input['receipt_number'] ?? null, 40);
        if ($receiptNumber === false) {
            $errors['receipt_number'] = 'Máximo 40 caracteres.';
        }
        $paymentMethod = $input['payment_method'] ?? null;
        if (!in_array($paymentMethod, self::PAYMENT_METHODS, true)) {
            $errors['payment_method'] = 'EFECTIVO o QR.';
        }
        $items = self::parseItems($input['items'] ?? null, $errors);
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        $total = array_sum(array_map(static fn (array $item): int => Quantity::lineTotalCents($item[1], $item[2]), $items));
        if ($total === 0) {
            throw new ApiException('PURCHASE_TOTAL_ZERO', 'El total de la compra debe ser mayor que 0.', 422);
        }

        $existing = $this->purchases->findByIdempotencyKey($key);
        if ($existing !== null) {
            return $this->replay($existing, $purchaseDate, $supplierId, $items);
        }

        try {
            $purchase = Db::transaction($this->db, function () use ($key, $purchaseDate, $supplierId, $receiptNumber, $paymentMethod, $items, $total): array {
                if ($supplierId !== null) {
                    $supplier = $this->suppliers->find($supplierId) ?? throw ApiException::validation(['supplier_id' => 'Proveedor inexistente.']);
                    if (!$supplier['is_active']) {
                        throw ApiException::conflict('SUPPLIER_INACTIVE', 'El proveedor está desactivado.');
                    }
                }
                $deltas = [];
                foreach ($items as [$ingredientId, $quantity]) {
                    $deltas[$ingredientId] = $quantity;
                }
                InventoryService::assertUsable($deltas, $this->inventory->lockAndCheck($deltas));

                $purchaseId = $this->purchases->insert([
                    'purchase_date' => $purchaseDate,
                    'supplier_id' => $supplierId,
                    'receipt_number' => $receiptNumber,
                    'payment_method' => $paymentMethod,
                    'total' => Money::fromCents($total),
                    'created_by' => $this->actor->id,
                    'idempotency_key' => $key,
                ]);
                foreach ($items as [$ingredientId, $quantity, $unitPrice]) {
                    $price = Money::fromCents($unitPrice);
                    $itemId = $this->purchases->insertItem($purchaseId, $ingredientId, Quantity::fromMilli($quantity), $price,
                        Money::fromCents(Quantity::lineTotalCents($quantity, $unitPrice)));
                    $this->inventory->move($ingredientId, 'ENTRADA_COMPRA', $quantity, $price, 'PURCHASE_ITEM', $itemId, null, $this->actor->id);
                }
                $this->finance->record('EGRESO', self::LEDGER_CATEGORY, "Compra #{$purchaseId}" . ($receiptNumber ? " (comprobante {$receiptNumber})" : ''),
                    Money::fromCents($total), 'PURCHASE', $purchaseId, $this->actor->id, $purchaseDate);

                $purchase = $this->get($purchaseId);
                Audit::log($this->db, $this->actor->id, 'purchases', $purchaseId, 'create', null, $purchase);
                return $purchase;
            });
        } catch (Throwable $e) {
            if (Db::isUniqueViolation($e, 'purchases_idempotency_key_key')) {
                $existing = $this->purchases->findByIdempotencyKey($key) ?? throw $e;
                return $this->replay($existing, $purchaseDate, $supplierId, $items);
            }
            throw $e;
        }
        return ['purchase' => $purchase, 'created' => true];
    }

    /** Si parte de lo comprado ya se usó, el stock no alcanza: 409 y primero un ajuste. */
    public function void(int $id, array $input): array
    {
        $reason = Validation::text($input['reason'] ?? null, 300)
            ?? throw ApiException::validation(['reason' => 'Requerido, máximo 300 caracteres.']);

        return Db::transaction($this->db, function () use ($id, $reason): array {
            $purchase = $this->purchases->find($id, forUpdate: true) ?? throw self::notFound();
            if ($purchase['status'] === 'ANULADA') {
                throw ApiException::conflict('PURCHASE_ALREADY_VOIDED', 'La compra ya está anulada.');
            }
            $items = $this->purchases->itemsFor([$id])[$id] ?? [];
            $deltas = [];
            foreach ($items as $item) {
                $deltas[(int) $item['ingredient_id']] = -Quantity::toMilli($item['quantity']);
            }
            $this->inventory->lockAndCheck($deltas);

            $description = "Anulación de la compra #{$id}: {$reason}";
            foreach ($items as $item) {
                $this->inventory->move((int) $item['ingredient_id'], 'REVERSO', -Quantity::toMilli($item['quantity']),
                    $item['unit_price'], 'PURCHASE_ITEM', (int) $item['id'], $description, $this->actor->id);
            }
            $this->finance->reverse('PURCHASE', $id, $description, $this->actor->id, $purchase['purchase_date']);
            $this->purchases->void($id, $this->actor->id, $reason);
            Audit::log($this->db, $this->actor->id, 'purchases', $id, 'void', ['status' => 'CONFIRMADA'],
                ['status' => 'ANULADA', 'reason' => $reason]);
            return $this->get($id);
        });
    }

    /** @return list<array{0: int, 1: int, 2: int}> [ingredient_id, milésimas, centavos por unidad] */
    private static function parseItems(mixed $items, array &$errors): array
    {
        if (!is_array($items) || !array_is_list($items) || $items === [] || count($items) > self::MAX_LINES) {
            $errors['items'] = 'Lista de 1 a ' . self::MAX_LINES . ' insumos.';
            return [];
        }
        $parsed = [];
        foreach ($items as $index => $item) {
            $ingredientId = is_array($item) ? Validation::positiveInt($item['ingredient_id'] ?? null) : null;
            $quantity = is_array($item) ? Validation::quantity($item['quantity'] ?? null) : null;
            $unitPrice = is_array($item) ? Validation::money($item['unit_price'] ?? null) : null;
            if ($ingredientId === null) {
                $errors["items.{$index}.ingredient_id"] = 'Requerido.';
            } elseif (in_array($ingredientId, array_column($parsed, 0), true)) {
                $errors["items.{$index}.ingredient_id"] = 'Insumo repetido: suma la cantidad en una sola línea.';
            }
            if ($quantity === null) {
                $errors["items.{$index}.quantity"] = 'Cantidad mayor que 0, hasta 99999.999 y con hasta 3 decimales.';
            }
            if ($unitPrice === null || $unitPrice > self::MAX_UNIT_PRICE_CENTS) {
                $errors["items.{$index}.unit_price"] = 'Precio unitario ≥ 0, hasta 1000000 y con hasta 2 decimales.';
            }
            if ($ingredientId !== null && $quantity !== null && $unitPrice !== null) {
                $parsed[] = [$ingredientId, $quantity, $unitPrice];
            }
        }
        return $parsed;
    }

    private function replay(array $existing, string $purchaseDate, ?int $supplierId, array $items): array
    {
        $id = (int) $existing['id'];
        $stored = array_map(static fn (array $item): array => [
            (int) $item['ingredient_id'], Quantity::toMilli($item['quantity']), Money::toCents($item['unit_price']),
        ], $this->purchases->itemsFor([$id])[$id] ?? []);
        sort($stored);
        sort($items);
        $sameSupplier = ($existing['supplier_id'] === null ? null : (int) $existing['supplier_id']) === $supplierId;
        if ((int) $existing['created_by'] !== $this->actor->id || $existing['purchase_date'] !== $purchaseDate
            || !$sameSupplier || $stored !== $items) {
            throw Idempotency::reused();
        }
        return ['purchase' => $this->detail($existing), 'created' => false];
    }

    /** Hoy en La Paz (fecha de calendario: una compra se fecha con la de la boleta, sin corte de jornada). */
    private function today(): string
    {
        return (string) $this->db->query('SELECT current_date::text')->fetchColumn();
    }

    private function detail(array $row): array
    {
        $id = (int) $row['id'];
        return self::toPublic($row, $this->purchases->itemsFor([$id])[$id] ?? []);
    }

    private static function toPublic(array $row, array $items): array
    {
        return [
            'id' => (int) $row['id'],
            'purchase_date' => $row['purchase_date'],
            'supplier' => $row['supplier_id'] === null ? null : ['id' => (int) $row['supplier_id'], 'name' => $row['supplier_name']],
            'receipt_number' => $row['receipt_number'],
            'payment_method' => $row['payment_method'],
            'items' => array_map(static fn (array $item): array => [
                'id' => (int) $item['id'],
                'ingredient' => ['id' => (int) $item['ingredient_id'], 'name' => $item['ingredient_name'], 'unit' => $item['unit_code']],
                'quantity' => $item['quantity'],
                'unit_price' => $item['unit_price'],
                'line_total' => $item['line_total'],
            ], $items),
            'total' => $row['total'],
            'status' => $row['status'],
            'created_by' => ['id' => (int) $row['created_by'], 'full_name' => $row['created_by_name']],
            'voided' => $row['status'] === 'ANULADA' ? [
                'by' => ['id' => (int) $row['voided_by'], 'full_name' => $row['voided_by_name']],
                'at' => Dates::iso($row['voided_at']),
                'reason' => $row['void_reason'],
            ] : null,
            'created_at' => Dates::iso($row['created_at']),
            'updated_at' => Dates::iso($row['updated_at']),
        ];
    }

    private static function notFound(): ApiException
    {
        return ApiException::notFound('Compra no encontrada.');
    }
}
