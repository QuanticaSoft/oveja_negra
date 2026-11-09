<?php

declare(strict_types=1);

final class PurchaseRepository
{
    private const SELECT = 'SELECT pu.*, s.name AS supplier_name, cu.full_name AS created_by_name, vu.full_name AS voided_by_name
                            FROM purchases pu
                            LEFT JOIN suppliers s ON s.id = pu.supplier_id
                            JOIN users cu ON cu.id = pu.created_by
                            LEFT JOIN users vu ON vu.id = pu.voided_by';

    public function __construct(private readonly PDO $db)
    {
    }

    public function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE pu.id = ?' . ($forUpdate ? ' FOR UPDATE OF pu' : ''));
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    public function findByIdempotencyKey(string $key): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE pu.idempotency_key = ?');
        $stmt->execute([$key]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    /**
     * @param array{from: string, to: string, supplier_id: ?int, status: ?string} $filters
     * @return array{rows: list<array>, total: int}
     */
    public function list(array $filters, int $limit, int $offset): array
    {
        $where = ['pu.purchase_date BETWEEN ? AND ?'];
        $params = [$filters['from'], $filters['to']];
        if ($filters['supplier_id'] !== null) {
            $where[] = 'pu.supplier_id = ?';
            $params[] = $filters['supplier_id'];
        }
        if ($filters['status'] !== null) {
            $where[] = 'pu.status = ?';
            $params[] = $filters['status'];
        }
        $whereSql = ' WHERE ' . implode(' AND ', $where);
        $count = $this->db->prepare('SELECT count(*) FROM purchases pu' . $whereSql);
        $count->execute($params);
        $stmt = $this->db->prepare(self::SELECT . $whereSql . ' ORDER BY pu.purchase_date DESC, pu.id DESC LIMIT ? OFFSET ?');
        $stmt->execute([...$params, $limit, $offset]);
        return ['rows' => $stmt->fetchAll(), 'total' => (int) $count->fetchColumn()];
    }

    public function insert(array $purchase): int
    {
        $stmt = $this->db->prepare(
            'INSERT INTO purchases (purchase_date, supplier_id, receipt_number, payment_method, total, created_by, idempotency_key)
             VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id'
        );
        $stmt->execute([$purchase['purchase_date'], $purchase['supplier_id'], $purchase['receipt_number'],
            $purchase['payment_method'], $purchase['total'], $purchase['created_by'], $purchase['idempotency_key']]);
        return (int) $stmt->fetchColumn();
    }

    public function insertItem(int $purchaseId, int $ingredientId, string $quantity, string $unitPrice, string $lineTotal): int
    {
        $stmt = $this->db->prepare(
            'INSERT INTO purchase_items (purchase_id, ingredient_id, quantity, unit_price, line_total) VALUES (?, ?, ?, ?, ?) RETURNING id'
        );
        $stmt->execute([$purchaseId, $ingredientId, $quantity, $unitPrice, $lineTotal]);
        return (int) $stmt->fetchColumn();
    }

    /**
     * @param list<int> $purchaseIds
     * @return array<int, list<array>> por compra
     */
    public function itemsFor(array $purchaseIds): array
    {
        if ($purchaseIds === []) {
            return [];
        }
        $stmt = $this->db->prepare(
            'SELECT pi.*, i.name AS ingredient_name, u.code AS unit_code
             FROM purchase_items pi JOIN ingredients i ON i.id = pi.ingredient_id JOIN units u ON u.id = i.unit_id
             WHERE pi.purchase_id IN (' . implode(', ', array_fill(0, count($purchaseIds), '?')) . ')
             ORDER BY pi.purchase_id, pi.id'
        );
        $stmt->execute($purchaseIds);
        $grouped = [];
        foreach ($stmt->fetchAll() as $row) {
            $grouped[(int) $row['purchase_id']][] = $row;
        }
        return $grouped;
    }

    public function void(int $purchaseId, int $userId, string $reason): void
    {
        $this->db->prepare(
            "UPDATE purchases SET status = 'ANULADA', voided_by = ?, voided_at = now(), void_reason = ? WHERE id = ?"
        )->execute([$userId, $reason, $purchaseId]);
    }
}
