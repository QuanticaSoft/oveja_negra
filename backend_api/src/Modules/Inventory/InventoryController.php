<?php

declare(strict_types=1);

final class InventoryController
{
    public function units(): never
    {
        Response::ok($this->ingredients()->units());
    }

    public function categories(): never
    {
        Response::ok($this->ingredients()->categories());
    }

    public function createCategory(): never
    {
        Response::ok($this->ingredients()->createCategory(Request::json()), 201);
    }

    public function index(): never
    {
        $result = $this->ingredients()->list(self::query(['category_id', 'active', 'low_stock', 'q', 'page', 'per_page']));
        Response::ok($result['data'], 200, $result['meta']);
    }

    public function show(string $id): never
    {
        Response::ok($this->ingredients()->get(self::ingredientId($id)));
    }

    public function create(): never
    {
        Response::ok($this->ingredients()->create(Request::json()), 201);
    }

    public function update(string $id): never
    {
        Response::ok($this->ingredients()->update(self::ingredientId($id), Request::json()));
    }

    public function setStatus(string $id): never
    {
        Response::ok($this->ingredients()->setActive(self::ingredientId($id), Request::json()));
    }

    public function movements(): never
    {
        $result = $this->inventory()->movements(self::query(['ingredient_id', 'type', 'from', 'to', 'page', 'per_page']));
        Response::ok($result['data'], 200, $result['meta']);
    }

    public function adjust(): never
    {
        Response::ok($this->inventory()->adjust(Request::json()), 201);
    }

    public function consume(): never
    {
        Response::ok($this->inventory()->consume(Request::json()), 201);
    }

    private function ingredients(): IngredientsService
    {
        return new IngredientsService(App::db(), App::user());
    }

    private function inventory(): InventoryService
    {
        return new InventoryService(App::db(), App::user(), App::config()['business_day_cutoff']);
    }

    /** @param list<string> $names */
    private static function query(array $names): array
    {
        $query = [];
        foreach ($names as $name) {
            $value = Request::query($name);
            if ($value !== null) {
                $query[$name] = $value;
            }
        }
        return $query;
    }

    private static function ingredientId(string $id): int
    {
        return Validation::positiveInt($id) ?? throw ApiException::notFound('Insumo no encontrado.');
    }
}
