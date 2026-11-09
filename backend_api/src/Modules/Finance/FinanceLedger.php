<?php

declare(strict_types=1);

/**
 * Único punto que escribe en financial_transactions (pagos ahora; compras y gastos en las
 * Fases 6 y 7). El UNIQUE (source_type, source_id, is_reversal) impide asentar dos veces lo mismo.
 */
final class FinanceLedger
{
    public function __construct(private readonly PDO $db, private readonly string $dayCutoff)
    {
    }

    /** $businessDate null = día operativo de ahora (corte de la jornada). */
    public function record(
        string $type,
        string $category,
        string $description,
        string $amount,
        string $sourceType,
        int $sourceId,
        int $createdBy,
        ?string $businessDate = null,
    ): int {
        $stmt = $this->db->prepare(
            'INSERT INTO financial_transactions
                 (type, category, description, amount, business_date, source_type, source_id, created_by)
             VALUES (?, ?, ?, ?, COALESCE(?::date, business_date_of(now(), ?::interval)), ?, ?, ?)
             RETURNING id'
        );
        $stmt->execute([$type, $category, $description, $amount, $businessDate, $this->dayCutoff,
            $sourceType, $sourceId, $createdBy]);
        return (int) $stmt->fetchColumn();
    }

    /**
     * Asienta el reverso (tipo contrario, mismo importe) en el día operativo de la anulación:
     * así la caja de cada día refleja el dinero que de verdad entró o salió ese día.
     */
    public function reverse(string $sourceType, int $sourceId, string $description, int $createdBy): int
    {
        $stmt = $this->db->prepare(
            "INSERT INTO financial_transactions
                 (type, category, description, amount, business_date, source_type, source_id,
                  is_reversal, reverses_id, created_by)
             SELECT CASE type WHEN 'INGRESO' THEN 'EGRESO' ELSE 'INGRESO' END, category, ?, amount,
                    business_date_of(now(), ?::interval), source_type, source_id, true, id, ?
             FROM financial_transactions
             WHERE source_type = ? AND source_id = ? AND NOT is_reversal
             RETURNING id"
        );
        $stmt->execute([$description, $this->dayCutoff, $createdBy, $sourceType, $sourceId]);
        $id = $stmt->fetchColumn();
        if ($id === false) {
            throw new LogicException("No hay movimiento financiero que revertir para {$sourceType} {$sourceId}.");
        }
        return (int) $id;
    }
}
