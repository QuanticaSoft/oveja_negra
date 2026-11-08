<?php

declare(strict_types=1);

final class RolesController
{
    public function index(): never
    {
        Response::ok($this->service()->list());
    }

    public function permissions(): never
    {
        Response::ok($this->service()->permissions());
    }

    public function replacePermissions(string $id): never
    {
        $roleId = Validation::positiveInt($id) ?? throw ApiException::notFound('Rol no encontrado.');
        Response::ok($this->service()->replacePermissions($roleId, Request::json()));
    }

    private function service(): RolesService
    {
        return new RolesService(App::db(), App::user());
    }
}
