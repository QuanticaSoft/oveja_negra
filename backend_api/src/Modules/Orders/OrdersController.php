<?php

declare(strict_types=1);

final class OrdersController
{
    public function index(): never
    {
        $query = array_filter([
            'from' => Request::query('from'),
            'to' => Request::query('to'),
            'status' => Request::query('status'),
            'channel' => Request::query('channel'),
            'sort' => Request::query('sort'),
            'page' => Request::query('page'),
            'per_page' => Request::query('per_page'),
        ], static fn (?string $value): bool => $value !== null);
        $result = $this->orders()->list($query);
        Response::ok($result['data'], 200, $result['meta']);
    }

    public function show(string $id): never
    {
        Response::ok($this->orders()->get(self::id($id)));
    }

    /** 201 al crear; 200 si es un reintento con la misma Idempotency-Key. */
    public function create(): never
    {
        $result = $this->orders()->create(Request::json(), Request::header(Idempotency::HEADER));
        Response::ok($result['order'], $result['created'] ? 201 : 200);
    }

    public function replaceItems(string $id): never
    {
        Response::ok($this->orders()->replaceItems(self::id($id), Request::json()));
    }

    public function changeStatus(string $id): never
    {
        Response::ok($this->orders()->changeStatus(self::id($id), Request::json()));
    }

    public function cancel(string $id): never
    {
        Response::ok($this->orders()->cancel(self::id($id), Request::json()));
    }

    public function createPayment(string $id): never
    {
        $result = $this->payments()->create(self::id($id), Request::json(), Request::header(Idempotency::HEADER));
        Response::ok($result['payment'], $result['created'] ? 201 : 200);
    }

    public function voidPayment(string $id): never
    {
        $paymentId = Validation::positiveInt($id) ?? throw ApiException::notFound('Pago no encontrado.');
        Response::ok($this->payments()->void($paymentId, Request::json()));
    }

    private function orders(): OrdersService
    {
        return new OrdersService(App::db(), App::user(), self::dayCutoff());
    }

    private function payments(): PaymentsService
    {
        return new PaymentsService(App::db(), App::user(), self::dayCutoff());
    }

    private static function dayCutoff(): string
    {
        return App::config()['business_day_cutoff'];
    }

    private static function id(string $id): int
    {
        return Validation::positiveInt($id) ?? throw ApiException::notFound('Pedido no encontrado.');
    }
}
