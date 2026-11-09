<?php

declare(strict_types=1);

/**
 * Lectura del libro financiero. Todos los totales son netos de reversos y se calculan en SQL
 * (NUMERIC), así lo cancelado o anulado suma 0 y el resultado cuadra con el libro.
 */
final class FinanceService
{
    private const TYPES = ['INGRESO', 'EGRESO'];
    // Importe con signo desde el punto de vista de la caja: entra (+) o sale (−).
    private const SIGNED = "CASE ft.type WHEN 'INGRESO' THEN ft.amount ELSE -ft.amount END";

    public function __construct(private readonly PDO $db, private readonly string $dayCutoff = '04:00')
    {
    }

    public function today(): string
    {
        $stmt = $this->db->prepare('SELECT business_date_of(now(), ?::interval)::text');
        $stmt->execute([$this->dayCutoff]);
        return (string) $stmt->fetchColumn();
    }

    /** @return array{data: list<array>, meta: array} */
    public function transactions(array $query): array
    {
        $today = $this->today();
        $range = DateRange::fromQuery($query, $today, $today);
        $where = ['ft.business_date BETWEEN ? AND ?'];
        $params = [$range->from, $range->to];
        if (isset($query['type'])) {
            if (!in_array($query['type'], self::TYPES, true)) {
                throw ApiException::validation(['type' => 'INGRESO o EGRESO.']);
            }
            $where[] = 'ft.type = ?';
            $params[] = $query['type'];
        }
        if (isset($query['category'])) {
            $where[] = 'ft.category = ?';
            $params[] = Validation::text($query['category'], 60) ?? throw ApiException::validation(['category' => 'Máximo 60 caracteres.']);
        }
        $pagination = Pagination::fromQuery($query);
        $whereSql = ' WHERE ' . implode(' AND ', $where);

        $count = $this->db->prepare('SELECT count(*) FROM financial_transactions ft' . $whereSql);
        $count->execute($params);
        $stmt = $this->db->prepare(
            'SELECT ft.*, u.full_name AS created_by_name FROM financial_transactions ft JOIN users u ON u.id = ft.created_by'
            . $whereSql . ' ORDER BY ft.business_date DESC, ft.id DESC LIMIT ? OFFSET ?'
        );
        $stmt->execute([...$params, $pagination->perPage, $pagination->offset()]);
        return [
            'data' => array_map(static fn (array $row): array => [
                'id' => (int) $row['id'],
                'type' => $row['type'],
                'category' => $row['category'],
                'description' => $row['description'],
                'amount' => $row['amount'],
                'business_date' => $row['business_date'],
                'occurred_at' => Dates::iso($row['occurred_at']),
                'source' => ['type' => $row['source_type'], 'id' => (int) $row['source_id']],
                'is_reversal' => (bool) $row['is_reversal'],
                'reverses_id' => $row['reverses_id'] === null ? null : (int) $row['reverses_id'],
                'created_by' => ['id' => (int) $row['created_by'], 'full_name' => $row['created_by_name']],
            ], $stmt->fetchAll()),
            'meta' => $pagination->meta((int) $count->fetchColumn()),
        ];
    }

    /** Cuadre del período: ventas cobradas − compras − gastos operativos = resultado operativo. */
    public function summaryFromQuery(array $query): array
    {
        $today = $this->today();
        $range = DateRange::fromQuery($query, $today, $today);
        return $this->summary($range->from, $range->to);
    }

    public function summary(string $from, string $to): array
    {
        $signed = self::SIGNED;
        $stmt = $this->db->prepare(
            "SELECT COALESCE(sum({$signed}) FILTER (WHERE ft.source_type = 'PAYMENT'), 0)::numeric(12,2)     AS collected,
                    COALESCE(sum({$signed}) FILTER (WHERE p.method = 'EFECTIVO'), 0)::numeric(12,2)          AS cash,
                    COALESCE(sum({$signed}) FILTER (WHERE p.method = 'QR'), 0)::numeric(12,2)                AS qr,
                    COALESCE(-sum({$signed}) FILTER (WHERE ft.source_type = 'PURCHASE'), 0)::numeric(12,2)   AS purchases,
                    COALESCE(-sum({$signed}) FILTER (WHERE ft.source_type = 'EXPENSE'), 0)::numeric(12,2)    AS expenses,
                    COALESCE(sum({$signed}), 0)::numeric(12,2)                                                AS result
             FROM financial_transactions ft
             LEFT JOIN payments p ON ft.source_type = 'PAYMENT' AND p.id = ft.source_id
             WHERE ft.business_date BETWEEN ? AND ?"
        );
        $stmt->execute([$from, $to]);
        $totals = $stmt->fetch();

        $byCategory = $this->db->prepare(
            "SELECT c.id, c.name, (-sum({$signed}))::numeric(12,2) AS total
             FROM financial_transactions ft
             JOIN expenses e ON e.id = ft.source_id
             JOIN expense_categories c ON c.id = e.category_id
             WHERE ft.source_type = 'EXPENSE' AND ft.business_date BETWEEN ? AND ?
             GROUP BY c.id, c.name
             HAVING sum({$signed}) <> 0
             ORDER BY total DESC, c.name"
        );
        $byCategory->execute([$from, $to]);

        return [
            'from' => $from,
            'to' => $to,
            'sales_collected' => ['total' => $totals['collected'], 'cash' => $totals['cash'], 'qr' => $totals['qr']],
            'purchases' => $totals['purchases'],
            'expenses' => [
                'total' => $totals['expenses'],
                'by_category' => array_map(static fn (array $row): array => [
                    'category' => ['id' => (int) $row['id'], 'name' => $row['name']], 'total' => $row['total'],
                ], $byCategory->fetchAll()),
            ],
            'operating_result' => $totals['result'],
        ];
    }
}
