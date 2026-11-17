<?php

declare(strict_types=1);

final class OrdersService
{
    public const CHANNELS = ['WHATSAPP', 'LOCAL'];
    public const FULFILLMENTS = ['CONSUMO_LOCAL', 'RECOGER', 'DELIVERY'];
    // Solo se avanza (se pueden saltar pasos); CANCELADO tiene su propio endpoint.
    private const STATUS_FLOW = ['PENDIENTE', 'EN_PREPARACION', 'LISTO', 'ENTREGADO'];
    private const STATUSES = [...self::STATUS_FLOW, 'CANCELADO'];
    private const MAX_LINES = 50;
    private const MAX_QUANTITY = 99;
    private const MAX_EXTRAS_PER_LINE = 10;
    private const MAX_EXTRA_QUANTITY = 5;
    private const DAILY_NUMBER_ATTEMPTS = 3;

    private readonly OrderRepository $orders;
    private readonly PaymentRepository $paymentRows;
    private readonly PaymentsService $payments;
    private readonly InventoryLedger $inventory;

    public function __construct(
        private readonly PDO $db,
        private readonly AuthUser $actor,
        private readonly string $dayCutoff = '04:00',
    ) {
        $this->orders = new OrderRepository($db);
        $this->paymentRows = new PaymentRepository($db);
        $this->payments = new PaymentsService($db, $actor, $dayCutoff);
        $this->inventory = new InventoryLedger($db);
    }

    /** @return array{data: list<array>, meta: array} */
    public function list(array $query): array
    {
        $today = $this->orders->currentBusinessDate($this->dayCutoff);
        $range = DateRange::fromQuery($query, $today, $today);

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
            ['from' => $range->from, 'to' => $range->to, 'statuses' => $statuses, 'channel' => $channel, 'ascending' => $sort === 'asc'],
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
        $customerPhone = Validation::looseOptionalPhone($input['customer_phone'] ?? null);
        if ($customerPhone === false) {
            $errors['customer_phone'] = 'Número de 7 a 15 dígitos, con "+" opcional.';
        }
        $notes = Validation::optionalText($input['notes'] ?? null, 500);
        if ($notes === false) {
            $errors['notes'] = 'Máximo 500 caracteres.';
        }
        $payments = self::parsePayments($input['payments'] ?? [], $errors);
        $delivery = self::parseFulfillment($input, $errors);
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
            return $this->replay($existing, $channel, $delivery, $items);
        }

        try {
            $order = Db::transaction($this->db, function () use ($key, $channel, $items, $discount, $customerName, $customerPhone, $notes, $payments, $delivery): array {
                [$lines, $subtotal, $consumption] = $this->price($items);
                self::assertDiscountFits($discount, $subtotal);
                $total = $subtotal - $discount + $delivery['fee'];
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
                    'fulfillment' => $delivery['fulfillment'],
                    'delivery_fee' => Money::fromCents($delivery['fee']),
                    'delivery_address' => $delivery['address'],
                    'delivery_references' => $delivery['references'],
                    'delivery_lat' => $delivery['lat'],
                    'delivery_lng' => $delivery['lng'],
                ]);
                $this->lockStockFor($consumption, $lines);
                // Los ítems van antes que los pagos: el trigger bloquea los ítems de un pedido con pagos.
                $this->orders->insertItems($orderId, $lines);
                $this->consumeExtras($orderId);
                foreach ($payments as [$method, $cents]) {
                    $this->payments->addToLockedOrder($this->orders->find($orderId), $method, $cents, null);
                }

                $order = $this->get($orderId);
                Audit::log($this->db, $this->actor->id, 'orders', $orderId, 'create', null, $order);
                return $order;
            });
        } catch (Throwable $e) {
            if (Db::isUniqueViolation($e, 'orders_idempotency_key_key')) {
                $existing = $this->orders->findByIdempotencyKey($key) ?? throw $e;
                return $this->replay($existing, $channel, $delivery, $items);
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
            [$lines, $subtotal, $consumption] = $this->price($items);
            self::assertDiscountFits($discount, $subtotal);

            $before = $this->detail($order);
            // Primero vuelve al stock lo que descontaron los extras anteriores; luego se descuenta lo nuevo.
            $this->reverseExtras($id, 'edición de ítems');
            $this->lockStockFor($consumption, $lines);
            $this->orders->deleteItems($id);
            $this->orders->insertItems($id, $lines);
            $this->consumeExtras($id);
            $this->orders->updateTotals($id, Money::fromCents($subtotal), Money::fromCents($discount));
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
            $this->reverseExtras($id, 'cancelación');
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
                    || !Db::isUniqueViolation($e, 'orders_business_date_daily_number_key')) {
                    throw $e;
                }
            }
        }
    }

    /**
     * Precios de productos y extras siempre desde la BD, nunca del cliente.
     * line_total = (precio + Σ precio_extra · cantidad_extra) × cantidad.
     *
     * @param list<array{product_id: int, quantity: int, notes: ?string, extras: array<int, int>}> $items
     * @return array{0: list<array>, 1: int, 2: array<int, int>}
     *         [líneas para order_items, subtotal en centavos, milésimas a descontar por insumo]
     */
    private function price(array $items): array
    {
        $products = $this->orders->productsForSale(array_column($items, 'product_id'));
        $extraIds = [];
        foreach ($items as $item) {
            array_push($extraIds, ...array_keys($item['extras']));
        }
        $extras = (new ExtraRepository($this->db))->forSale($extraIds);
        $allowed = $this->orders->allowedExtras(array_map(static fn (array $p): int => (int) $p['category_id'], array_values($products)));
        $errors = [];
        $unavailable = [];
        $unavailableExtras = [];
        $lines = [];
        $subtotal = 0;
        $consumption = [];
        foreach ($items as $index => $item) {
            $product = $products[$item['product_id']] ?? null;
            if ($product === null) {
                $errors["items.{$index}.product_id"] = 'Producto inexistente.';
                continue;
            }
            if (!$product['sellable']) {
                $unavailable[] = ['id' => $item['product_id'], 'name' => $product['name']];
                continue;
            }
            $extrasUnit = 0;
            $lineExtras = [];
            foreach ($item['extras'] as $extraId => $extraQuantity) {
                $extra = $extras[$extraId] ?? null;
                if ($extra === null) {
                    $errors["items.{$index}.extras"] = "Extra inexistente: {$extraId}.";
                    continue;
                }
                if (!in_array($extraId, $allowed[(int) $product['category_id']] ?? [], true)) {
                    $errors["items.{$index}.extras"] = "{$extra['name']} no se puede agregar a {$product['name']}.";
                    continue;
                }
                if (!$extra['sellable']) {
                    $unavailableExtras[$extraId] = ['id' => $extraId, 'name' => $extra['name']];
                    continue;
                }
                $extrasUnit += Money::toCents($extra['price']) * $extraQuantity;
                $lineExtras[] = [
                    'extra_id' => $extraId,
                    'name' => $extra['name'],
                    'unit_price' => $extra['price'],
                    'quantity' => $extraQuantity,
                    'ingredient_id' => $extra['ingredient_id'] === null ? null : (int) $extra['ingredient_id'],
                    'ingredient_quantity' => $extra['ingredient_quantity'],
                ];
                if ($extra['ingredient_id'] !== null) {
                    $ingredientId = (int) $extra['ingredient_id'];
                    $consumption[$ingredientId] = ($consumption[$ingredientId] ?? 0)
                        + Quantity::toMilli($extra['ingredient_quantity']) * $extraQuantity * $item['quantity'];
                }
            }
            $lineCents = (Money::toCents($product['price']) + $extrasUnit) * $item['quantity'];
            $subtotal += $lineCents;
            $lines[] = [
                'product_id' => $item['product_id'],
                'name' => $product['name'],
                'unit_price' => $product['price'],
                'quantity' => $item['quantity'],
                'line_total' => Money::fromCents($lineCents),
                'notes' => $item['notes'],
                'extras_unit_total' => Money::fromCents($extrasUnit),
                'extras' => $lineExtras,
            ];
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($unavailable !== []) {
            throw new ApiException('PRODUCT_UNAVAILABLE', 'Hay productos agotados o desactivados en el pedido.', 409,
                ['products' => $unavailable]);
        }
        if ($unavailableExtras !== []) {
            throw new ApiException('EXTRA_UNAVAILABLE', 'Hay extras agotados o desactivados en el pedido.', 409,
                ['extras' => array_values($unavailableExtras)]);
        }
        return [$lines, $subtotal, $consumption];
    }

    /**
     * Bloquea los insumos de los extras y verifica el stock antes de guardar nada.
     *
     * @param array<int, int> $consumption milésimas por insumo
     */
    private function lockStockFor(array $consumption, array $lines): void
    {
        if ($consumption === []) {
            return;
        }
        try {
            $this->inventory->lockAndCheck(array_map(static fn (int $milli): int => -$milli, $consumption));
        } catch (ApiException $e) {
            if ($e->errorCode !== 'INSUFFICIENT_STOCK') {
                throw $e;
            }
            $short = array_column($e->details['ingredients'], 'ingredient_id');
            $extras = [];
            foreach ($lines as $line) {
                foreach ($line['extras'] as $extra) {
                    if (in_array($extra['ingredient_id'], $short, true)) {
                        $extras[$extra['extra_id']] = ['id' => $extra['extra_id'], 'name' => $extra['name']];
                    }
                }
            }
            throw new ApiException('EXTRA_OUT_OF_STOCK', 'No hay stock suficiente para algunos extras.', 409, [
                'extras' => array_values($extras),
                'ingredients' => $e->details['ingredients'],
            ]);
        }
    }

    /** Una SALIDA_CONSUMO por cada extra con insumo (ya verificado y bloqueado por lockStockFor). */
    private function consumeExtras(int $orderId): void
    {
        $number = $this->orders->find($orderId)['daily_number'];
        foreach ($this->orders->extrasWithIngredient($orderId) as $extra) {
            $this->inventory->move((int) $extra['ingredient_id'], 'SALIDA_CONSUMO', -Quantity::toMilli($extra['total_quantity']),
                null, 'ORDER_ITEM_EXTRA', (int) $extra['id'], "Pedido #{$number}: extra {$extra['name_snapshot']}", $this->actor->id);
        }
    }

    /** Devuelve al stock lo que descontaron los extras del pedido (REVERSO, sin tocar el costo promedio). */
    private function reverseExtras(int $orderId, string $why): void
    {
        $extras = $this->orders->extrasWithIngredient($orderId);
        if ($extras === []) {
            return;
        }
        $this->inventory->lockAndCheck(array_fill_keys(array_map(static fn (array $e): int => (int) $e['ingredient_id'], $extras), 0));
        $number = $this->orders->find($orderId)['daily_number'];
        foreach ($extras as $extra) {
            $this->inventory->move((int) $extra['ingredient_id'], 'REVERSO', Quantity::toMilli($extra['total_quantity']),
                null, 'ORDER_ITEM_EXTRA', (int) $extra['id'], "Pedido #{$number}: {$why} (extra {$extra['name_snapshot']})", $this->actor->id);
        }
    }

    /** Un reintento con la misma clave devuelve el pedido ya creado; con otro contenido es un error del cliente. */
    private function replay(array $existing, string $channel, array $delivery, array $items): array
    {
        $stored = array_map(static fn (array $item): array => [
            'product_id' => (int) $item['product_id'],
            'quantity' => (int) $item['quantity'],
            'notes' => $item['notes'],
            'extras' => self::extrasMap($item['extras']),
        ], $this->orders->itemsFor([(int) $existing['id']])[(int) $existing['id']] ?? []);
        if ((int) $existing['created_by'] !== $this->actor->id || $existing['channel'] !== $channel
            || $existing['fulfillment'] !== $delivery['fulfillment']
            || Money::toCents($existing['delivery_fee']) !== $delivery['fee']
            || self::fingerprint($stored) !== self::fingerprint($items)) {
            throw Idempotency::reused();
        }
        return ['order' => $this->detail($existing), 'created' => false];
    }

    /** Contenido comparable de los ítems, sin depender del orden. */
    private static function fingerprint(array $items): array
    {
        $rows = array_map(static fn (array $i): string => json_encode([$i['product_id'], $i['quantity'], $i['notes'] ?? '', $i['extras']]), $items);
        sort($rows);
        return $rows;
    }

    /** @return array<int, int> extra_id => cantidad, ordenado por id */
    private static function extrasMap(array $extras): array
    {
        $map = [];
        foreach ($extras as $e) {
            $map[(int) $e['extra_id']] = (int) $e['quantity'];
        }
        ksort($map);
        return $map;
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
     * El mismo producto puede ir en varias líneas (con otros extras u otra nota).
     *
     * @return list<array{product_id: int, quantity: int, notes: ?string, extras: array<int, int>}>
     */
    private static function parseItems(mixed $items, array &$errors): array
    {
        if (!is_array($items) || !array_is_list($items) || $items === [] || count($items) > self::MAX_LINES) {
            $errors['items'] = 'Lista de 1 a ' . self::MAX_LINES . ' productos.';
            return [];
        }
        $parsed = [];
        foreach ($items as $index => $item) {
            $item = is_array($item) ? $item : [];
            $productId = Validation::positiveInt($item['product_id'] ?? null);
            $quantity = $item['quantity'] ?? null;
            if ($productId === null) {
                $errors["items.{$index}.product_id"] = 'Requerido.';
            }
            if (!is_int($quantity) || $quantity < 1 || $quantity > self::MAX_QUANTITY) {
                $errors["items.{$index}.quantity"] = 'Entero de 1 a ' . self::MAX_QUANTITY . '.';
            }
            $notes = Validation::optionalText($item['notes'] ?? null, 200);
            if ($notes === false) {
                $errors["items.{$index}.notes"] = 'Máximo 200 caracteres.';
            }
            $extras = self::parseExtras($item['extras'] ?? [], "items.{$index}.extras", $errors);
            if ($productId !== null && is_int($quantity) && $notes !== false) {
                $parsed[] = ['product_id' => $productId, 'quantity' => $quantity, 'notes' => $notes, 'extras' => $extras];
            }
        }
        return $parsed;
    }

    /** @return array<int, int> extra_id => cantidad (1 a 5), ordenado por id */
    private static function parseExtras(mixed $extras, string $field, array &$errors): array
    {
        if (!is_array($extras) || !array_is_list($extras) || count($extras) > self::MAX_EXTRAS_PER_LINE) {
            $errors[$field] = 'Lista de hasta ' . self::MAX_EXTRAS_PER_LINE . ' extras.';
            return [];
        }
        $map = [];
        foreach ($extras as $extra) {
            $extraId = is_array($extra) ? Validation::positiveInt($extra['extra_id'] ?? null) : null;
            $quantity = is_array($extra) ? ($extra['quantity'] ?? 1) : null;
            if ($extraId === null || !is_int($quantity) || $quantity < 1 || $quantity > self::MAX_EXTRA_QUANTITY) {
                $errors[$field] = 'Cada extra: {extra_id, quantity de 1 a ' . self::MAX_EXTRA_QUANTITY . '}.';
                continue;
            }
            if (isset($map[$extraId])) {
                $errors[$field] = 'Extra repetido en la misma línea: usa su cantidad.';
                continue;
            }
            $map[$extraId] = $quantity;
        }
        ksort($map);
        return $map;
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

    /**
     * Modalidad y datos de entrega. El envío y la dirección solo existen en DELIVERY.
     *
     * @return array{fulfillment: string, fee: int, address: ?string, references: ?string, lat: ?string, lng: ?string}
     */
    private static function parseFulfillment(array $input, array &$errors): array
    {
        $fulfillment = $input['fulfillment'] ?? 'CONSUMO_LOCAL';
        $none = ['fulfillment' => $fulfillment, 'fee' => 0, 'address' => null, 'references' => null, 'lat' => null, 'lng' => null];
        if (!in_array($fulfillment, self::FULFILLMENTS, true)) {
            $errors['fulfillment'] = 'Uno de: ' . implode(', ', self::FULFILLMENTS) . '.';
            return $none;
        }
        $delivery = $input['delivery'] ?? null;
        if ($fulfillment !== 'DELIVERY') {
            if ($delivery !== null) {
                $errors['delivery'] = 'Solo se envía con fulfillment DELIVERY.';
            }
            return $none;
        }
        if (!is_array($delivery)) {
            $errors['delivery'] = 'Requerido para DELIVERY: {address, fee, references, lat, lng}.';
            return $none;
        }

        $fee = Validation::money($delivery['fee'] ?? 0);
        if ($fee === null) {
            $errors['delivery.fee'] = 'Importe ≥ 0 con hasta 2 decimales.';
        }
        $address = Validation::text($delivery['address'] ?? null, 300);
        if ($address === null) {
            $errors['delivery.address'] = 'Requerida, máximo 300 caracteres.';
        }
        $references = Validation::optionalText($delivery['references'] ?? null, 300);
        if ($references === false) {
            $errors['delivery.references'] = 'Máximo 300 caracteres.';
        }
        $lat = $lng = null;
        if (($delivery['lat'] ?? null) !== null || ($delivery['lng'] ?? null) !== null) {
            $lat = Validation::coordinate($delivery['lat'] ?? null, 90);
            $lng = Validation::coordinate($delivery['lng'] ?? null, 180);
            if ($lat === null || $lng === null) {
                $errors['delivery.location'] = 'lat (-90 a 90) y lng (-180 a 180), las dos o ninguna.';
            }
        }
        return [
            'fulfillment' => $fulfillment,
            'fee' => $fee ?? 0,
            'address' => $address,
            'references' => $references === false ? null : $references,
            'lat' => $lat,
            'lng' => $lng,
        ];
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

    private static function auditItems(array $order): array
    {
        return [
            'items' => array_map(static fn (array $item): array => [
                $item['product_id'], $item['quantity'], $item['unit_price'], $item['notes'],
                array_map(static fn (array $e): array => [$e['extra_id'], $e['quantity'], $e['unit_price']], $item['extras']),
            ], $order['items']),
            'subtotal' => $order['subtotal'],
            'discount' => $order['discount'],
            'delivery_fee' => $order['delivery_fee'],
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
            'fulfillment' => $row['fulfillment'],
            'delivery' => $row['fulfillment'] === 'DELIVERY' ? [
                'address' => $row['delivery_address'],
                'references' => $row['delivery_references'],
                'lat' => $row['delivery_lat'],
                'lng' => $row['delivery_lng'],
            ] : null,
            'items' => array_map(static fn (array $item): array => [
                'id' => (int) $item['id'],
                'product_id' => (int) $item['product_id'],
                'name' => $item['product_name_snapshot'],
                'unit_price' => $item['unit_price_snapshot'],
                'quantity' => (int) $item['quantity'],
                'notes' => $item['notes'],
                'extras' => array_map(static fn (array $e): array => [
                    'extra_id' => (int) $e['extra_id'],
                    'name' => $e['name_snapshot'],
                    'unit_price' => $e['unit_price_snapshot'],
                    'quantity' => (int) $e['quantity'],
                ], $item['extras']),
                'extras_unit_total' => $item['extras_unit_total'],
                'line_total' => $item['line_total'],
            ], $items),
            'subtotal' => $row['subtotal'],
            'discount' => $row['discount'],
            'delivery_fee' => $row['delivery_fee'],
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
