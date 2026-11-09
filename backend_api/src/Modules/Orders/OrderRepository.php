<?php

declare(strict_types=1);

final class OrderRepository
{
    // paid y balance se calculan siempre desde los pagos confirmados: no hay columna que pueda desincronizarse.
    private const SELECT = "SELECT o.*, cu.full_name AS created_by_name, xu.full_name AS cancelled_by_name,
                                   p.paid, (o.total - p.paid)::numeric(12,2) AS balance
                            FROM orders o
                            JOIN users cu ON cu.id = o.created_by
                            LEFT JOIN users xu ON xu.id = o.cancelled_by
                            CROSS JOIN LATERAL (
                                SELECT COALESCE(sum(amount), 0)::numeric(12,2) AS paid
                                FROM payments WHERE order_id = o.id AND status = 'CONFIRMADO'
                            ) p";

    public function __construct(private readonly PDO $db)
    {
    }

    /** Lee primero el bloqueo y después las columnas calculadas (FOR UPDATE no admite agregados). */
    public function find(int $id, bool $forUpdate = false): ?array
    {
        if ($forUpdate) {
            $lock = $this->db->prepare('SELECT id FROM orders WHERE id = ? FOR UPDATE');
            $lock->execute([$id]);
            if ($lock->fetchColumn() === false) {
                return null;
            }
        }
        $stmt = $this->db->prepare(self::SELECT . ' WHERE o.id = ?');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    public function findByIdempotencyKey(string $key): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE o.idempotency_key = ?');
        $stmt->execute([$key]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    /**
     * @param array{from: string, to: string, statuses: list<string>, channel: ?string, ascending: bool} $filters
     * @return array{rows: list<array>, total: int}
     */
    public function list(array $filters, int $limit, int $offset): array
    {
        $where = ['o.business_date BETWEEN ? AND ?'];
        $params = [$filters['from'], $filters['to']];
        if ($filters['statuses'] !== []) {
            $where[] = 'o.status IN (' . implode(', ', array_fill(0, count($filters['statuses']), '?')) . ')';
            array_push($params, ...$filters['statuses']);
        }
        if ($filters['channel'] !== null) {
            $where[] = 'o.channel = ?';
            $params[] = $filters['channel'];
        }
        $whereSql = ' WHERE ' . implode(' AND ', $where);
        $direction = $filters['ascending'] ? 'ASC' : 'DESC';

        $count = $this->db->prepare('SELECT count(*) FROM orders o' . $whereSql);
        $count->execute($params);
        $stmt = $this->db->prepare(self::SELECT . $whereSql
            . " ORDER BY o.business_date {$direction}, o.daily_number {$direction} LIMIT ? OFFSET ?");
        $stmt->execute([...$params, $limit, $offset]);

        return ['rows' => $stmt->fetchAll(), 'total' => (int) $count->fetchColumn()];
    }

    public function currentBusinessDate(string $dayCutoff): string
    {
        $stmt = $this->db->prepare('SELECT business_date_of(now(), ?::interval)::text');
        $stmt->execute([$dayCutoff]);
        return (string) $stmt->fetchColumn();
    }

    /** daily_number = último del día + 1; si otra caja ganó la carrera, el UNIQUE lo rechaza y se reintenta. */
    public function insert(array $order): int
    {
        $stmt = $this->db->prepare(
            'INSERT INTO orders (business_date, daily_number, channel, subtotal, discount, total,
                                 customer_name, customer_phone, notes, created_by, idempotency_key)
             VALUES (?, (SELECT COALESCE(max(daily_number), 0) + 1 FROM orders WHERE business_date = ?),
                     ?, ?, ?, ?, ?, ?, ?, ?, ?)
             RETURNING id'
        );
        $stmt->execute([
            $order['business_date'], $order['business_date'], $order['channel'], $order['subtotal'],
            $order['discount'], $order['total'], $order['customer_name'], $order['customer_phone'],
            $order['notes'], $order['created_by'], $order['idempotency_key'],
        ]);
        return (int) $stmt->fetchColumn();
    }

    /** @param list<array{product_id: int, name: string, unit_price: string, quantity: int, line_total: string}> $items */
    public function insertItems(int $orderId, array $items): void
    {
        $stmt = $this->db->prepare(
            'INSERT INTO order_items (order_id, product_id, product_name_snapshot, unit_price_snapshot, quantity, line_total)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        foreach ($items as $item) {
            $stmt->execute([$orderId, $item['product_id'], $item['name'], $item['unit_price'], $item['quantity'], $item['line_total']]);
        }
    }

    /** Solo posible con el pedido PENDIENTE y sin pagos: lo garantiza el trigger guard_order_items_change. */
    public function deleteItems(int $orderId): void
    {
        $this->db->prepare('DELETE FROM order_items WHERE order_id = ?')->execute([$orderId]);
    }

    public function updateTotals(int $orderId, string $subtotal, string $discount, string $total): void
    {
        $this->db->prepare('UPDATE orders SET subtotal = ?, discount = ?, total = ? WHERE id = ?')
            ->execute([$subtotal, $discount, $total, $orderId]);
    }

    public function setStatus(int $orderId, string $status): void
    {
        $this->db->prepare('UPDATE orders SET status = ? WHERE id = ?')->execute([$status, $orderId]);
    }

    public function cancel(int $orderId, int $userId, string $reason): void
    {
        $this->db->prepare(
            "UPDATE orders SET status = 'CANCELADO', cancelled_by = ?, cancelled_at = now(), cancel_reason = ? WHERE id = ?"
        )->execute([$userId, $reason, $orderId]);
    }

    /**
     * @param list<int> $orderIds
     * @return array<int, list<array>> ítems agrupados por pedido
     */
    public function itemsFor(array $orderIds): array
    {
        if ($orderIds === []) {
            return [];
        }
        $stmt = $this->db->prepare(
            'SELECT id, order_id, product_id, product_name_snapshot, unit_price_snapshot, quantity, line_total
             FROM order_items WHERE order_id IN (' . implode(', ', array_fill(0, count($orderIds), '?')) . ')
             ORDER BY order_id, id'
        );
        $stmt->execute($orderIds);
        $grouped = [];
        foreach ($stmt->fetchAll() as $row) {
            $grouped[(int) $row['order_id']][] = $row;
        }
        return $grouped;
    }

    /**
     * Productos pedidos con su precio actual y si se pueden vender.
     *
     * @param list<int> $productIds
     * @return array<int, array> por id de producto
     */
    public function productsForSale(array $productIds): array
    {
        $stmt = $this->db->prepare(
            'SELECT p.id, p.name, p.price, p.is_active AND p.is_available AND c.is_active AS sellable
             FROM products p JOIN categories c ON c.id = p.category_id
             WHERE p.id IN (' . implode(', ', array_fill(0, count($productIds), '?')) . ')'
        );
        $stmt->execute($productIds);
        return array_column($stmt->fetchAll(), null, 'id');
    }
}
