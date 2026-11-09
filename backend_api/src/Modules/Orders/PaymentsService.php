<?php

declare(strict_types=1);

/** Cada pago confirmado es un INGRESO; anularlo crea el EGRESO de reverso. Nunca se edita ni se borra. */
final class PaymentsService
{
    public const METHODS = ['EFECTIVO', 'QR'];
    public const LEDGER_CATEGORY = 'VENTA';

    private readonly OrderRepository $orders;
    private readonly PaymentRepository $payments;
    private readonly FinanceLedger $ledger;

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor, string $dayCutoff = '04:00')
    {
        $this->orders = new OrderRepository($db);
        $this->payments = new PaymentRepository($db);
        $this->ledger = new FinanceLedger($db, $dayCutoff);
    }

    /** @return array{payment: array, created: bool} created = false si es un reintento con la misma clave */
    public function create(int $orderId, array $input, ?string $idempotencyKey): array
    {
        $key = Idempotency::key($idempotencyKey);
        [$method, $cents] = self::parse($input);

        $existing = $this->payments->findByIdempotencyKey($key);
        if ($existing !== null) {
            return $this->replay($existing, $orderId, $method, $cents);
        }

        try {
            $payment = Db::transaction($this->db, function () use ($orderId, $method, $cents, $key): array {
                $order = $this->orders->find($orderId, forUpdate: true) ?? throw self::orderNotFound();
                return $this->payments->find($this->addToLockedOrder($order, $method, $cents, $key));
            });
        } catch (Throwable $e) {
            // Dos reintentos simultáneos: el que pierde la carrera devuelve el pago del ganador.
            if (Db::isUniqueViolation($e, 'payments_idempotency_key_key')) {
                $existing = $this->payments->findByIdempotencyKey($key) ?? throw $e;
                return $this->replay($existing, $orderId, $method, $cents);
            }
            throw $e;
        }
        return ['payment' => self::toPublic($payment), 'created' => true];
    }

    public function void(int $paymentId, array $input): array
    {
        $reason = Validation::text($input['reason'] ?? null, 300)
            ?? throw ApiException::validation(['reason' => 'Requerido, máximo 300 caracteres.']);

        return Db::transaction($this->db, function () use ($paymentId, $reason): array {
            $orderId = $this->payments->orderIdOf($paymentId) ?? throw ApiException::notFound('Pago no encontrado.');
            // Mismo orden de bloqueo que al cobrar (pedido → pago) para no crear interbloqueos.
            $order = $this->orders->find($orderId, forUpdate: true);
            $payment = $this->payments->find($paymentId, forUpdate: true);
            if ($payment['status'] === 'ANULADO') {
                throw ApiException::conflict('PAYMENT_ALREADY_VOIDED', 'El pago ya está anulado.');
            }
            $this->voidLocked($payment, $order, $reason);
            return self::toPublic($this->payments->find($paymentId));
        });
    }

    /**
     * Registra un pago sobre un pedido ya bloqueado (FOR UPDATE) en la transacción actual.
     * $order debe estar leído después del bloqueo: su "paid" es el que se usa contra el sobrepago.
     */
    public function addToLockedOrder(array $order, string $method, int $cents, ?string $idempotencyKey): int
    {
        if ($order['status'] === 'CANCELADO') {
            throw ApiException::conflict('ORDER_CANCELLED', 'El pedido está cancelado.');
        }
        $balance = Money::toCents($order['total']) - Money::toCents($order['paid']);
        if ($cents > $balance) {
            throw new ApiException('OVERPAYMENT', 'El pago supera el saldo del pedido.', 422,
                ['balance' => Money::fromCents($balance)]);
        }

        $amount = Money::fromCents($cents);
        $paymentId = $this->payments->insert((int) $order['id'], $method, $amount, $this->actor->id, $idempotencyKey);
        $this->ledger->record('INGRESO', self::LEDGER_CATEGORY,
            "Pago #{$paymentId} ({$method}) del pedido #{$order['daily_number']} del {$order['business_date']}",
            $amount, 'PAYMENT', $paymentId, $this->actor->id);
        Audit::log($this->db, $this->actor->id, 'payments', $paymentId, 'create', null,
            ['order_id' => (int) $order['id'], 'method' => $method, 'amount' => $amount]);
        return $paymentId;
    }

    /** Anula un pago bloqueado y asienta su reverso. Lo usa también la cancelación del pedido. */
    public function voidLocked(array $payment, array $order, string $reason): void
    {
        $paymentId = (int) $payment['id'];
        $this->payments->void($paymentId, $this->actor->id, $reason);
        $this->ledger->reverse('PAYMENT', $paymentId,
            "Anulación del pago #{$paymentId} del pedido #{$order['daily_number']} del {$order['business_date']}: {$reason}",
            $this->actor->id);
        Audit::log($this->db, $this->actor->id, 'payments', $paymentId, 'void',
            ['status' => 'CONFIRMADO'], ['status' => 'ANULADO', 'reason' => $reason]);
    }

    /**
     * @return array{0: string, 1: int} [método, centavos]
     * @throws ApiException 400 con los errores bajo "$prefix.method" / "$prefix.amount"
     */
    public static function parse(mixed $input, string $prefix = ''): array
    {
        $errors = [];
        $method = is_array($input) ? ($input['method'] ?? null) : null;
        if (!in_array($method, self::METHODS, true)) {
            $errors[$prefix . 'method'] = 'EFECTIVO o QR.';
        }
        $cents = is_array($input) ? Validation::money($input['amount'] ?? null) : null;
        if ($cents === null || $cents === 0) {
            $errors[$prefix . 'amount'] = 'Importe mayor que 0 con hasta 2 decimales.';
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        return [$method, $cents];
    }

    public static function toPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'order_id' => (int) $row['order_id'],
            'method' => $row['method'],
            'amount' => $row['amount'],
            'status' => $row['status'],
            'received_by' => ['id' => (int) $row['received_by'], 'full_name' => $row['received_by_name']],
            'created_at' => Dates::iso($row['created_at']),
            'voided' => $row['status'] === 'ANULADO' ? [
                'by' => ['id' => (int) $row['voided_by'], 'full_name' => $row['voided_by_name']],
                'at' => Dates::iso($row['voided_at']),
                'reason' => $row['void_reason'],
            ] : null,
        ];
    }

    private function replay(array $existing, int $orderId, string $method, int $cents): array
    {
        $same = (int) $existing['order_id'] === $orderId
            && $existing['method'] === $method
            && Money::toCents($existing['amount']) === $cents
            && (int) $existing['received_by'] === $this->actor->id;
        if (!$same) {
            throw Idempotency::reused();
        }
        return ['payment' => self::toPublic($existing), 'created' => false];
    }

    private static function orderNotFound(): ApiException
    {
        return ApiException::notFound('Pedido no encontrado.');
    }
}
