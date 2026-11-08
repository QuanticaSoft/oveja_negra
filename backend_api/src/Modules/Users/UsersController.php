<?php

declare(strict_types=1);

final class UsersController
{
    public function index(): never
    {
        $result = $this->service()->list(array_filter([
            'active' => Request::query('active'),
            'role' => Request::query('role'),
            'page' => Request::query('page'),
            'per_page' => Request::query('per_page'),
        ], static fn (?string $value): bool => $value !== null));
        Response::ok($result['data'], 200, $result['meta']);
    }

    public function show(string $id): never
    {
        Response::ok($this->service()->get(self::userId($id)));
    }

    public function create(): never
    {
        Response::ok($this->service()->create(Request::json()), 201);
    }

    public function update(string $id): never
    {
        Response::ok($this->service()->update(self::userId($id), Request::json()));
    }

    public function setStatus(string $id): never
    {
        Response::ok($this->service()->setStatus(self::userId($id), Request::json()));
    }

    public function resetPassword(string $id): never
    {
        Response::ok($this->service()->resetPassword(self::userId($id), Request::json()));
    }

    private function service(): UsersService
    {
        return new UsersService(App::db(), App::user());
    }

    private static function userId(string $id): int
    {
        return Validation::positiveInt($id) ?? throw ApiException::notFound('Usuario no encontrado.');
    }
}
