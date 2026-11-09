<?php

declare(strict_types=1);

/** Gasto confirmado = un EGRESO en su fecha. No se edita: se anula (reverso en la misma fecha) y se registra otro. */
final class ExpensesService
{
    public const LEDGER_CATEGORY = 'GASTO_OPERATIVO';
    private const PAYMENT_METHODS = ['EFECTIVO', 'QR'];
    private const STATUSES = ['CONFIRMADO', 'ANULADO'];
    private const SELECT = 'SELECT e.*, c.name AS category_name, cu.full_name AS created_by_name, vu.full_name AS voided_by_name
                            FROM expenses e
                            JOIN expense_categories c ON c.id = e.category_id
                            JOIN users cu ON cu.id = e.created_by
                            LEFT JOIN users vu ON vu.id = e.voided_by';

    private readonly ExpenseCategoriesService $categories;
    private readonly FinanceLedger $ledger;

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor, string $dayCutoff = '04:00')
    {
        $this->categories = new ExpenseCategoriesService($db, $actor);
        $this->ledger = new FinanceLedger($db, $dayCutoff);
    }

    /** @return array{data: list<array>, meta: array} por defecto, los últimos 30 días */
    public function list(array $query): array
    {
        $today = $this->today();
        $range = DateRange::fromQuery($query, (new DateTimeImmutable($today))->modify('-29 days')->format('Y-m-d'), $today);
        $where = ['e.expense_date BETWEEN ? AND ?'];
        $params = [$range->from, $range->to];
        if (isset($query['category_id'])) {
            $where[] = 'e.category_id = ?';
            $params[] = Validation::positiveInt($query['category_id'])
                ?? throw ApiException::validation(['category_id' => 'Entero positivo.']);
        }
        if (isset($query['status'])) {
            if (!in_array($query['status'], self::STATUSES, true)) {
                throw ApiException::validation(['status' => 'CONFIRMADO o ANULADO.']);
            }
            $where[] = 'e.status = ?';
            $params[] = $query['status'];
        }
        $pagination = Pagination::fromQuery($query);
        $whereSql = ' WHERE ' . implode(' AND ', $where);

        $count = $this->db->prepare('SELECT count(*) FROM expenses e' . $whereSql);
        $count->execute($params);
        $stmt = $this->db->prepare(self::SELECT . $whereSql . ' ORDER BY e.expense_date DESC, e.id DESC LIMIT ? OFFSET ?');
        $stmt->execute([...$params, $pagination->perPage, $pagination->offset()]);
        return ['data' => array_map(self::toPublic(...), $stmt->fetchAll()), 'meta' => $pagination->meta((int) $count->fetchColumn())];
    }

    public function get(int $id): array
    {
        return self::toPublic($this->find($id) ?? throw self::notFound());
    }

    /** @return array{expense: array, created: bool} created = false si es un reintento con la misma clave */
    public function create(array $input, ?string $idempotencyKey): array
    {
        $key = Idempotency::key($idempotencyKey);
        $errors = [];
        $date = Validation::date($input['expense_date'] ?? null);
        if ($date === null) {
            $errors['expense_date'] = 'Fecha YYYY-MM-DD.';
        } elseif ($date > $this->today()) {
            $errors['expense_date'] = 'No puede ser una fecha futura.';
        }
        $categoryId = Validation::positiveInt($input['category_id'] ?? null);
        if ($categoryId === null) {
            $errors['category_id'] = 'Requerido.';
        }
        $description = Validation::text($input['description'] ?? null, 300);
        if ($description === null) {
            $errors['description'] = 'Requerido, máximo 300 caracteres.';
        }
        $cents = Validation::money($input['amount'] ?? null);
        if ($cents === null || $cents === 0) {
            $errors['amount'] = 'Importe mayor que 0 con hasta 2 decimales.';
        }
        $method = $input['payment_method'] ?? null;
        if (!in_array($method, self::PAYMENT_METHODS, true)) {
            $errors['payment_method'] = 'EFECTIVO o QR.';
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        $request = ['expense_date' => $date, 'category_id' => $categoryId, 'description' => $description,
                    'amount' => Money::fromCents($cents), 'payment_method' => $method];

        $existing = $this->findByIdempotencyKey($key);
        if ($existing !== null) {
            return $this->replay($existing, $request);
        }

        try {
            $expense = Db::transaction($this->db, function () use ($key, $request): array {
                $category = $this->categories->find($request['category_id'])
                    ?? throw ApiException::validation(['category_id' => 'Categoría inexistente.']);
                if (!$category['is_active']) {
                    throw ApiException::conflict('EXPENSE_CATEGORY_INACTIVE', 'La categoría de gasto está desactivada.');
                }
                $stmt = $this->db->prepare(
                    'INSERT INTO expenses (expense_date, category_id, description, amount, payment_method, created_by, idempotency_key)
                     VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id'
                );
                $stmt->execute([$request['expense_date'], $request['category_id'], $request['description'],
                    $request['amount'], $request['payment_method'], $this->actor->id, $key]);
                $id = (int) $stmt->fetchColumn();
                $this->ledger->record('EGRESO', self::LEDGER_CATEGORY, "Gasto #{$id} ({$category['name']}): {$request['description']}",
                    $request['amount'], 'EXPENSE', $id, $this->actor->id, $request['expense_date']);
                $expense = $this->get($id);
                Audit::log($this->db, $this->actor->id, 'expenses', $id, 'create', null, $expense);
                return $expense;
            });
        } catch (Throwable $e) {
            if (Db::isUniqueViolation($e, 'expenses_idempotency_key_key')) {
                $existing = $this->findByIdempotencyKey($key) ?? throw $e;
                return $this->replay($existing, $request);
            }
            throw $e;
        }
        return ['expense' => $expense, 'created' => true];
    }

    /** El reverso va en la fecha del gasto: anular corrige la carga de ese día. */
    public function void(int $id, array $input): array
    {
        $reason = Validation::text($input['reason'] ?? null, 300)
            ?? throw ApiException::validation(['reason' => 'Requerido, máximo 300 caracteres.']);

        return Db::transaction($this->db, function () use ($id, $reason): array {
            $expense = $this->find($id, forUpdate: true) ?? throw self::notFound();
            if ($expense['status'] === 'ANULADO') {
                throw ApiException::conflict('EXPENSE_ALREADY_VOIDED', 'El gasto ya está anulado.');
            }
            $this->ledger->reverse('EXPENSE', $id, "Anulación del gasto #{$id}: {$reason}", $this->actor->id, $expense['expense_date']);
            $this->db->prepare("UPDATE expenses SET status = 'ANULADO', voided_by = ?, voided_at = now(), void_reason = ? WHERE id = ?")
                ->execute([$this->actor->id, $reason, $id]);
            Audit::log($this->db, $this->actor->id, 'expenses', $id, 'void', ['status' => 'CONFIRMADO'],
                ['status' => 'ANULADO', 'reason' => $reason]);
            return $this->get($id);
        });
    }

    private function replay(array $existing, array $request): array
    {
        $same = (int) $existing['created_by'] === $this->actor->id
            && $existing['expense_date'] === $request['expense_date']
            && (int) $existing['category_id'] === $request['category_id']
            && $existing['description'] === $request['description']
            && $existing['amount'] === $request['amount']
            && $existing['payment_method'] === $request['payment_method'];
        if (!$same) {
            throw Idempotency::reused();
        }
        return ['expense' => self::toPublic($existing), 'created' => false];
    }

    private function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE e.id = ?' . ($forUpdate ? ' FOR UPDATE OF e' : ''));
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    private function findByIdempotencyKey(string $key): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE e.idempotency_key = ?');
        $stmt->execute([$key]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    private function today(): string
    {
        return (string) $this->db->query('SELECT current_date::text')->fetchColumn();
    }

    private static function toPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'expense_date' => $row['expense_date'],
            'category' => ['id' => (int) $row['category_id'], 'name' => $row['category_name']],
            'description' => $row['description'],
            'amount' => $row['amount'],
            'payment_method' => $row['payment_method'],
            'status' => $row['status'],
            'created_by' => ['id' => (int) $row['created_by'], 'full_name' => $row['created_by_name']],
            'voided' => $row['status'] === 'ANULADO' ? [
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
        return ApiException::notFound('Gasto no encontrado.');
    }
}
