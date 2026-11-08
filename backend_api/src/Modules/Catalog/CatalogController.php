<?php

declare(strict_types=1);

final class CatalogController
{
    public function menu(): never
    {
        Response::ok($this->productsService()->menu());
    }

    public function categories(): never
    {
        Response::ok($this->categoriesService()->list(['active' => Request::query('active')]));
    }

    public function createCategory(): never
    {
        Response::ok($this->categoriesService()->create(Request::json()), 201);
    }

    public function updateCategory(string $id): never
    {
        Response::ok($this->categoriesService()->update(self::id($id, 'Categoría'), Request::json()));
    }

    public function products(): never
    {
        $query = array_filter([
            'category_id' => Request::query('category_id'),
            'active' => Request::query('active'),
            'available' => Request::query('available'),
            'q' => Request::query('q'),
            'page' => Request::query('page'),
            'per_page' => Request::query('per_page'),
        ], static fn (?string $value): bool => $value !== null);
        $result = $this->productsService()->list($query);
        Response::ok($result['data'], 200, $result['meta']);
    }

    public function product(string $id): never
    {
        Response::ok($this->productsService()->get(self::id($id)));
    }

    public function createProduct(): never
    {
        Response::ok($this->productsService()->create(Request::json()), 201);
    }

    public function updateProduct(string $id): never
    {
        Response::ok($this->productsService()->update(self::id($id), Request::json()));
    }

    public function changePrice(string $id): never
    {
        Response::ok($this->productsService()->changePrice(self::id($id), Request::json()));
    }

    public function setStatus(string $id): never
    {
        Response::ok($this->productsService()->setActive(self::id($id), Request::json()));
    }

    public function setAvailability(string $id): never
    {
        Response::ok($this->productsService()->setAvailability(self::id($id), Request::json()));
    }

    public function uploadImage(string $id): never
    {
        $productId = self::id($id);
        Response::ok($this->productsService()->replaceImage($productId, ImageProcessor::uploadedFile($_FILES['image'] ?? null)));
    }

    public function priceHistory(string $id): never
    {
        Response::ok($this->productsService()->priceHistory(self::id($id)));
    }

    private function productsService(): ProductsService
    {
        return new ProductsService(App::db(), App::user(), new Media(App::config()));
    }

    private function categoriesService(): CategoriesService
    {
        return new CategoriesService(App::db(), App::user());
    }

    private static function id(string $id, string $entity = 'Producto'): int
    {
        return Validation::positiveInt($id) ?? throw ApiException::notFound("{$entity} no encontrado.");
    }
}
