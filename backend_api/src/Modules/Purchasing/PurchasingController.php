<?php

declare(strict_types=1);

final class PurchasingController
{
    public function suppliers(): never
    {
        Response::ok($this->suppliersService()->list(['active' => Request::query('active')]));
    }

    public function createSupplier(): never
    {
        Response::ok($this->suppliersService()->create(Request::json()), 201);
    }

    public function updateSupplier(string $id): never
    {
        $supplierId = Validation::positiveInt($id) ?? throw ApiException::notFound('Proveedor no encontrado.');
        Response::ok($this->suppliersService()->update($supplierId, Request::json()));
    }

    public function purchases(): never
    {
        $result = $this->purchasesService()->list(QueryParams::only(['from', 'to', 'supplier_id', 'status', 'page', 'per_page']));
        Response::ok($result['data'], 200, $result['meta']);
    }

    public function purchase(string $id): never
    {
        Response::ok($this->purchasesService()->get(self::purchaseId($id)));
    }

    /** 201 al crear; 200 si es un reintento con la misma Idempotency-Key. */
    public function createPurchase(): never
    {
        $result = $this->purchasesService()->create(Request::json(), Request::header(Idempotency::HEADER));
        Response::ok($result['purchase'], $result['created'] ? 201 : 200);
    }

    public function voidPurchase(string $id): never
    {
        Response::ok($this->purchasesService()->void(self::purchaseId($id), Request::json()));
    }

    private function suppliersService(): SuppliersService
    {
        return new SuppliersService(App::db(), App::user());
    }

    private function purchasesService(): PurchasesService
    {
        return new PurchasesService(App::db(), App::user(), App::config()['business_day_cutoff']);
    }

    private static function purchaseId(string $id): int
    {
        return Validation::positiveInt($id) ?? throw ApiException::notFound('Compra no encontrada.');
    }
}
