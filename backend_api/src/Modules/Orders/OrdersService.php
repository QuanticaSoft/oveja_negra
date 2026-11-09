<?php

declare(strict_types=1);

final class OrdersService
{
    public const CHANNELS = ['WHATSAPP', 'LOCAL'];
    // Solo se avanza (se pueden saltar pasos); CANCELADO tiene su propio endpoint.
    private const STATUS_FLOW = ['PENDIENTE', 'EN_PREPARACION', 'LISTO', 'ENTREGADO'];
    private const STATUSES = [...self::STATUS_FLOW, 'CANCELADO'];
    private const MAX_LINES = 50;
    private const MAX_QUANTITY = 99;
    private const MAX_RANGE_DAYS = 92;
    private const DAILY_NUMBER_ATTEMPTS = 3;

    private readonly OrderRepository $orders;
    private readonly PaymentRepository $paymentRows;
    private readonly PaymentsService $payments;

    public function __construct(
        private readonly PDO $db,
        private readonly AuthUser $actor,
        private readonly string $dayCutoff = '04:00',
    ) {
        $this->orders = new OrderRepository($db);
        $this->paymentRows = new PaymentRepository($db);
        $this->payments = new PaymentsService($db, $actor, $dayCutoff);
    }

    /** @return array{data: list<array>, meta: array} */
    public function list(array $query): array
    {
        $today = $this->orders->currentBusinessDate($this->dayCutoff);
        $from = self::date($query['from'] ?? $today, 'from');
        $to = self::date($query['to'] ?? $today, 'to');
        if ($from > $to) {
            throw ApiException::validation(['from' => 'Debe ser anterior o igual a "to".']);
        }
        if ((new DateTimeImmutable($from))->diff(new DateTimeImmutable($to))->days >= self::MAX_RANGE_DAYS) {
            throw ApiException::validation(['to' => 'El rango máximo es de ' . self::MAX_RANGE_DAYS . ' días.']);
        }

        $statuses = isset($query['status']) ? array_values(array_unique(explode(',', strtoupper($query['status'])))) : [];
        if (array_diff($statuses, self::STATUSES) !== []) {
            throw ApiException::validation(['status' => 'Uno o varios de: ' . implode(', ', self::STATUSES) . ' (separados por coma).']);
        }
        $channel = isset($query['channel']) ? strtoupper($query['channel']) : null;
        if ($channel !== null && !in_array($channel, self::CHANNELS, true)) {
            throw ApiException::validation(['channel' => 'WHATSAPP o LOCAL.']);
        }
        $sort = $query['sort'] ?? 'desc';
        if (!in_array($sort, ['asc', 'desc'], true)) {
            throw ApiException::validation(['sort' => 'asc o desc.']);
        }
        $pagination = Pagination::fromQuery($query);

        $result = $this->orders->list(
            ['from' => $from, 'to' => $to, 'statuses' => $statuses, 'channel' => $channel, 'ascending' => $sort === 'asc'],
            $pagination->perPage, $pagination->offset());
        $items = $this->orders->itemsFor(array_map(static fn (array $row): int => (int) $row['id'], $result['rows']));
        $data = array_map(fn (array $row): array => self::toPublic($row, $items[(int) $row['id']] ?? []), $result['rows']);
        return ['data' => $data, 'meta' => $pagination->meta($result['total'])];
    }

    public function get(int $id): array
    {
        return $this->detail($this->orders->find($id) ?? throw self::notFound());
    }

    /**
     * Pedido, ítems y pagos iniciales en una sola transacción: si algo falla no queda nada.
     *
     * @return array{order: array, created: bool} created = false si es un reintento con la misma clave
     */
    public function create(array $input, ?string $idempotencyKey): array
    {
        $key = Idempotency::key($idempotencyKey);
        $errors = [];
        $channel = $input['channel'] ?? null;
        if (!in_array($channel, self::CHANNELS, true)) {
            $errors['channel'] = 'WHATSAPP o LOCAL.';
        }
        $items = self::parseItems($input['items'] ?? null, $errors);
        $discount = self::discount($input, $errors) ?? 0;
        $customerName = Validation::optionalText($input['customer_name'] ?? null, 120);
        if ($customerName === false) {
            $errors['customer_name'] = 'Máximo 120 caracteres.';
        }
        $customerPhone = self::customerPhone($input['customer_phone'] ?? null);
        if ($customerPhone === false) {
            $errors['customer_phone'] = 'Número de 7 a 15 dígitos, con "+" opcional.';
        }
        $notes = Validation::optionalText($input['notes'] ?? null, 500);
        if ($notes === false) {
            $errors['notes'] = 'Máximo 500 caracteres.';
        }
        $payments = self::parsePayments($input['payments'] ?? [], $errors);
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($discount > 0) {
            $this->requirePermission('orders.discount');
        }
        if ($payments !== []) {
            $this->requirePermission('payments.create');
        }

        $existing = $this->orders->findByIdempotencyKey($key);
        if ($existing !== null) {
            return $this->replay($existing, $channel, $items);
        }

        try {
            $order = Db::transaction($this->db, function () use ($key, $channel, $items, $discount, $customerName, $customerPhone, $notes, $payments): array {
                [$lines, $subtotal] = $this->price($items);
                self::assertDiscountFits($discount, $subtotal);
                $total = $subtotal - $discount;
                if (array_sum(array_column($payments, 1)) > $total) {
                    throw new ApiException('OVERPAYMENT', 'Los pagos superan el total del pedido.', 422,
                        ['balance' => Money::fromCents($total)]);
                }

                $orderId = $this->insertWithDailyNumber([
                    'business_date' => $this->orders->currentBusinessDate($this->dayCutoff),
                    'channel' => $channel,
                    'subtotal' => Money::fromCents($subtotal),
                    'discount' => Money::fromCents($discount),
                    'total' => Money::fromCents($total),
                    'customer_name' => $customerName,
                    'customer_phone' => $customerPhone,
                    'notes' => $notes,
                    'created_by' => $this->actor->id,
                    'idempotency_key' => $key,
                ]);
                // Los ítems van antes que los pagos: el trigger bloquea los ítems de un pedido con pagos.
                $this->orders->insertItems($orderId, $lines);
                foreach ($payments as [$method, $cents]) {
                    $this->payments->addToLockedOrder($this->orders->find($orderId), $method, $cents, null);
                }

                $order = $this->get($orderId);
                Audit::log($this->db, $this->actor->id, 'orders', $orderId, 'create', null, $order);
                return $order;
            });
        } catch (Throwable $e) {
            if (Idempotency::isUniqueViolation($e, 'orders_idempotency_key_key')) {
                $existing = $this->orders->findByIdempotencyKey($key) ?? throw $e;
                return $this->replay($existing, $channel, $items);
            }
            throw $e;
        }
        return ['order' => $order, 'created' => true];
    }

    /** Reemplaza todos los ítems. Solo con el pedido PENDIENTE y sin pagos; si no, se cancela y se crea otro. */
    public function replaceItems(int $id, array $input): array
    {
        $errors = [];
        $items = self::parseItems($input['items'] ?? null, $errors);
        $newDiscount = self::discount($input, $errors);
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }

        return Db::transaction($this->db, function () use ($id, $items, $newDiscount): array {
            $order = $this->orders->find($id, forUpdate: true) ?? throw self::notFound();
            if ($order['status'] !== 'PENDIENTE' || Money::toCents($order['paid']) > 0) {
                throw ApiException::conflict('ORDER_LOCKED',
                    'Solo se editan pedidos PENDIENTES y sin pagos. Cancélalo y registra uno nuevo.');
            }
            $discount = $newDiscount ?? Money::toCents($order['discount']);
            if ($discount !== Money::toCents($order['discount'])) {
                $this->requirePermission('orders.discount');
            }
            [$lines, $subtotal] = $this->price($items);
            self::assertDiscountFits($discount, $subtotal);

            $before = $this->detail($order);
            $this->orders->deleteItems($id);
            $this->orders->insertItems($id, $lines);
            $this->orders->updateTotals($id, Money::fromCents($subtotal), Money::fromCents($discount),
                Money::fromCents($subtotal - $discount));
            $after = $this->get($id);
            Audit::log($this->db, $this->actor->id, 'orders', $id, 'replace_items',
                self::auditItems($before), self::auditItems($after));
            return $after;
        });
    }

    public function changeStatus(int $id, array $input): array
    {
        $status = $input['status'] ?? null;
        if ($status === 'CANCELADO') {
            throw ApiException::validation(['status' => 'Para cancelar usa POST /v1/orders/{id}/cancel (pide un motivo).']);
        }
        if (!in_array($status, self::STATUS_FLOW, true)) {
            throw ApiException::validation(['status' => 'Uno de: ' . implode(', ', self::STATUS_FLOW) . '.']);
        }

        return Db::transaction($this->db, function () use ($id, $status): array {
            $order = $this->orders->find($id, forUpdate: true) ?? throw self::notFound();
            $current = $order['status'];
            if ($current === 'CANCELADO') {
                throw ApiException::conflict('ORDER_CANCELLED', 'El pedido está cancelado.');
            }
            if ($current === $status) {
                return $this->detail($order);
            }
            if (array_search($status, self::STATUS_FLOW, true) < array_search($current, self::STATUS_FLOW, true)) {
                throw ApiException::conflict('INVALID_TRANSITION', "Un pedido {$current} no puede volver a {$status}.");
            }
            if ($status === 'ENTREGADO' && Money::toCents($order['balance']) > 0) {
                throw new ApiException('UNPAID_ORDER', 'El pedido debe estar pagado por completo antes de entregarlo.', 422,
                    ['balance' => $order['balance']]);
            }
            $this->orders->setStatus($id, $status);
            Audit::log($this->db, $this->actor->id, 'orders', $id, 'change_status', ['status' => $current], ['status' => $status]);
            return $this->get($id);
        });
    }

    /** Anula los pagos confirmados (cada uno con su reverso): lo cancelado no queda como ingreso. */
    public function cancel(int $id, array $input): array
    {
        $reason = Validation::text($input['reason'] ?? null, 300)
            ?? throw ApiException::validation(['reason' => 'Requerido, máximo 300 caracteres.']);

        return Db::transaction($this->db, function () use ($id, $reason): array {
            $order = $this->orders->find($id, forUpdate: true) ?? throw self::notFound();
            if ($order['status'] === 'CANCELADO') {
                throw ApiException::conflict('ORDER_CANCELLED', 'El pedido ya está cancelado.');
            }
            if ($order['status'] === 'ENTREGADO') {
                throw ApiException::conflict('INVALID_TRANSITION', 'Un pedido entregado no se puede cancelar.');
            }
            foreach ($this->paymentRows->forOrder($id, confirmedOnly: true) as $payment) {
                $this->payments->voidLocked($payment, $order, "Pedido cancelado: {$reason}");
            }
            $this->orders->cancel($id, $this->actor->id, $reason);
            Audit::log($this->db, $this->actor->id, 'orders', $id, 'cancel',
                ['status' => $order['status'], 'paid' => $order['paid']], ['status' => 'CANCELADO', 'reason' => $reason]);
            return $this->get($id);
        });
    }

    private function insertWithDailyNumber(array $order): int
    {
        for ($attempt = 1; ; $attempt++) {
            try {
                // Savepoint propio: si otra caja tomó el mismo número, se reintenta sin perder la transacción.
                return Db::transaction($this->db, fn (): int => $this->orders->insert($order));
            } catch (PDOException $e) {
                if ($attempt >= self::DAILY_NUMBER_ATTEMPTS
                    || !Idempotency::isUniqueViolation($e, 'orders_business_date_daily_number_key')) {
                    throw $e;
                }
            }
        }
    }

    /**
     * Precios siempre desde la BD, nunca del cliente.
     *
     * @param list<array{0: int, 1: int}> $items [product_id, quantity]
     * @return array{0: list<array>, 1: int} [líneas para order_items, subtotal en centavos]
     */
    private function price(array $items): array
    {
        $products = $this->orders->productsForSale(array_column($items, 0));
        $errors = [];
        $unavailable = [];
        $lines = [];
        $subtotal = 0;
        foreach ($items as $index => [$productId, $quantity]) {
            $product = $products[$productId] ?? null;
            if ($product === null) {
                $errors["items.{$index}.product_id"] = 'Producto inexistente.';
                continue;
            }
            if (!$product['sellable']) {
                $unavailable[] = ['id' => $productId, 'name' => $product['name']];
                continue;
            }
            $lineCents = Money::toCents($product['price']) * $quantity;
            $subtotal += $lineCents;
            $lines[] = [
                'product_id' => $productId,
                'name' => $product['name'],
                'unit_price' => $product['price'],
                'quantity' => $quantity,
                'line_total' => Money::fromCents($lineCents),
            ];
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($unavailable !== []) {
            throw new ApiException('PRODUCT_UNAVAILABLE', 'Hay productos agotados o desactivados en el pedido.', 409,
                ['products' => $unavailable]);
        }
        return [$lines, $subtotal];
    }

    /** Un reintento con la misma clave devuelve el pedido ya creado; con otro contenido es un error del cliente. */
    private function replay(array $existing, string $channel, array $items): array
    {
        $stored = array_map(static fn (array $item): array => [(int) $item['product_id'], (int) $item['quantity']],
            $this->orders->itemsFor([(int) $existing['id']])[(int) $existing['id']] ?? []);
        sort($stored);
        sort($items);
        if ((int) $existing['created_by'] !== $this->actor->id || $existing['channel'] !== $channel || $stored !== $items) {
            throw Idempotency::reused();
        }
        return ['order' => $this->detail($existing), 'created' => false];
    }

    private function detail(array $row): array
    {
        $id = (int) $row['id'];
        return self::toPublic($row, $this->orders->itemsFor([$id])[$id] ?? [])
            + ['payments' => array_map(PaymentsService::toPublic(...), $this->paymentRows->forOrder($id))];
    }

    private static function notFound(): ApiException
    {
        return ApiException::notFound('Pedido no encontrado.');
    }

    private function requirePermission(string $permission): void
    {
        if (!$this->actor->can($permission)) {
            throw new ApiException('FORBIDDEN', "No tienes permiso para esta acción ({$permission}).", 403);
        }
    }

    /**
     * @return list<array{0: int, 1: int}> [product_id, quantity]
     */
    private static function parseItems(mixed $items, array &$errors): array
    {
        if (!is_array($items) || !array_is_list($items) || $items === [] || count($items) > self::MAX_LINES) {
            $errors['items'] = 'Lista de 1 a ' . self::MAX_LINES . ' productos.';
            return [];
        }
        $parsed = [];
        foreach ($items as $index => $item) {
            $productId = is_array($item) ? Validation::positiveInt($item['product_id'] ?? null) : null;
            $quantity = is_array($item) ? ($item['quantity'] ?? null) : null;
            if ($productId === null) {
                $errors["items.{$index}.product_id"] = 'Requerido.';
            } elseif (in_array($productId, array_column($parsed, 0), true)) {
                $errors["items.{$index}.product_id"] = 'Producto repetido: suma la cantidad en una sola línea.';
            }
            if (!is_int($quantity) || $quantity < 1 || $quantity > self::MAX_QUANTITY) {
                $errors["items.{$index}.quantity"] = 'Entero de 1 a ' . self::MAX_QUANTITY . '.';
            }
            if ($productId !== null && is_int($quantity)) {
                $parsed[] = [$productId, $quantity];
            }
        }
        return $parsed;
    }

    /** @return list<array{0: string, 1: int}> [método, centavos] */
    private static function parsePayments(mixed $payments, array &$errors): array
    {
        if (!is_array($payments) || !array_is_list($payments) || count($payments) > 5) {
            $errors['payments'] = 'Lista de hasta 5 pagos.';
            return [];
        }
        $parsed = [];
        foreach ($payments as $index => $payment) {
            try {
                $parsed[] = PaymentsService::parse($payment, "payments.{$index}.");
            } catch (ApiException $e) {
                $errors += $e->details;
            }
        }
        return $parsed;
    }

    /** null si no viene en el input. */
    private static function discount(array $input, array &$errors): ?int
    {
        if (!array_key_exists('discount', $input)) {
            return null;
        }
        $cents = Validation::money($input['discount']);
        if ($cents === null) {
            $errors['discount'] = 'Importe ≥ 0 con hasta 2 decimales.';
        }
        return $cents;
    }

    private static function assertDiscountFits(int $discount, int $subtotal): void
    {
        if ($discount > $subtotal) {
            throw new ApiException('DISCOUNT_EXCEEDS_SUBTOTAL', 'El descuento no puede superar el subtotal.', 422,
                ['subtotal' => Money::fromCents($subtotal)]);
        }
    }

    /** Clientes de WhatsApp pueden tener número extranjero: no se exige +591. */
    private static function customerPhone(mixed $value): string|null|false
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (!is_string($value)) {
            return false;
        }
        $phone = preg_replace('/[\s-]/', '', $value);
        return preg_match('/^\+?\d{7,15}$/', $phone) ? $phone : false;
    }

    private static function date(mixed $value, string $field): string
    {
        if (!is_string($value) || !preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $value, $m)
            || !checkdate((int) $m[2], (int) $m[3], (int) $m[1])) {
            throw ApiException::validation([$field => 'Fecha YYYY-MM-DD.']);
        }
        return $value;
    }

    private static function auditItems(array $order): array
    {
        return [
            'items' => array_map(static fn (array $item): array => [$item['product_id'], $item['quantity'], $item['unit_price']], $order['items']),
            'subtotal' => $order['subtotal'],
            'discount' => $order['discount'],
            'total' => $order['total'],
        ];
    }

    private static function toPublic(array $row, array $items): array
    {
        $total = Money::toCents($row['total']);
        $paid = Money::toCents($row['paid']);
        return [
            'id' => (int) $row['id'],
            'number' => (int) $row['daily_number'],
            'business_date' => $row['business_date'],
            'channel' => $row['channel'],
            'status' => $row['status'],
            'customer_name' => $row['customer_name'],
            'customer_phone' => $row['customer_phone'],
            'notes' => $row['notes'],
            'items' => array_map(static fn (array $item): array => [
                'id' => (int) $item['id'],
                'product_id' => (int) $item['product_id'],
                'name' => $item['product_name_snapshot'],
                'unit_price' => $item['unit_price_snapshot'],
                'quantity' => (int) $item['quantity'],
                'line_total' => $item['line_total'],
            ], $items),
            'subtotal' => $row['subtotal'],
            'discount' => $row['discount'],
            'total' => $row['total'],
            'paid' => $row['paid'],
            'balance' => $row['balance'],
            'payment_status' => match (true) {
                $paid >= $total => 'PAGADO',
                $paid === 0 => 'SIN_PAGAR',
                default => 'PARCIAL',
            },
            'created_by' => ['id' => (int) $row['created_by'], 'full_name' => $row['created_by_name']],
            'cancelled' => $row['status'] === 'CANCELADO' ? [
                'by' => ['id' => (int) $row['cancelled_by'], 'full_name' => $row['cancelled_by_name']],
                'at' => Dates::iso($row['cancelled_at']),
                'reason' => $row['cancel_reason'],
            ] : null,
            'created_at' => Dates::iso($row['created_at']),
            'updated_at' => Dates::iso($row['updated_at']),
        ];
    }
}
