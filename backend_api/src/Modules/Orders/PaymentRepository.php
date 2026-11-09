<?php

declare(strict_types=1);

final class PaymentRepository
{
    private const SELECT = 'SELECT pm.*, ru.full_name AS received_by_name, vu.full_name AS voided_by_name
                            FROM payments pm
                            JOIN users ru ON ru.id = pm.received_by
                            LEFT JOIN users vu ON vu.id = pm.voided_by';

    public function __construct(private readonly PDO $db)
    {
    }

    public function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE pm.id = ?' . ($forUpdate ? ' FOR UPDATE OF pm' : ''));
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    public function findByIdempotencyKey(string $key): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE pm.idempotency_key = ?');
        $stmt->execute([$key]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    public function orderIdOf(int $paymentId): ?int
    {
        $stmt = $this->db->prepare('SELECT order_id FROM payments WHERE id = ?');
        $stmt->execute([$paymentId]);
        $orderId = $stmt->fetchColumn();
        return $orderId === false ? null : (int) $orderId;
    }

    /** @return list<array> */
    public function forOrder(int $orderId, bool $confirmedOnly = false): array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE pm.order_id = ?'
            . ($confirmedOnly ? " AND pm.status = 'CONFIRMADO'" : '') . ' ORDER BY pm.id');
        $stmt->execute([$orderId]);
        return $stmt->fetchAll();
    }

    public function insert(int $orderId, string $method, string $amount, int $receivedBy, ?string $idempotencyKey): int
    {
        $stmt = $this->db->prepare(
            'INSERT INTO payments (order_id, method, amount, received_by, idempotency_key) VALUES (?, ?, ?, ?, ?) RETURNING id'
        );
        $stmt->execute([$orderId, $method, $amount, $receivedBy, $idempotencyKey]);
        return (int) $stmt->fetchColumn();
    }

    public function void(int $paymentId, int $userId, string $reason): void
    {
        $this->db->prepare(
            "UPDATE payments SET status = 'ANULADO', voided_by = ?, voided_at = now(), void_reason = ? WHERE id = ?"
        )->execute([$userId, $reason, $paymentId]);
    }
}
