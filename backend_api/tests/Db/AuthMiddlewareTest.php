<?php

declare(strict_types=1);

final class AuthMiddlewareTest extends DbTestCase
{
    public function testSinTokenOTokenInvalido(): void
    {
        $this->assertApiError('UNAUTHENTICATED', 401, fn () => $this->authenticate(null, 'orders.create'));
        $this->assertApiError('UNAUTHENTICATED', 401, fn () => $this->authenticate('no.es.jwt', 'orders.create'));
    }

    public function testTokenExpirado(): void
    {
        $id = $this->insertUser('ADMIN', 'admin.test');
        $this->assertApiError('UNAUTHENTICATED', 401,
            fn () => $this->authenticate($this->token($id, expiresIn: -1), 'users.manage'));
    }

    public function testUsuarioDesactivadoConTokenVigente(): void
    {
        $id = $this->insertUser('CAJERO', 'cajero.test');
        $token = $this->token($id);
        $this->db->prepare('UPDATE users SET is_active = false WHERE id = ?')->execute([$id]);
        $this->assertApiError('USER_INACTIVE', 401, fn () => $this->authenticate($token, 'orders.create'));
    }

    public function testPermisosDelCajero(): void
    {
        $token = $this->token($this->insertUser('CAJERO', 'cajero.test'));
        $this->assertSame('CAJERO', $this->authenticate($token, 'orders.create')->roleCode);
        $this->authenticate($token, 'payments.create');
        foreach (['users.manage', 'orders.cancel', 'payments.void', 'purchases.create', 'reports.read', 'dashboard.read', 'finance.read', 'expenses.create'] as $denied) {
            $this->assertApiError('FORBIDDEN', 403, fn () => $this->authenticate($token, $denied));
        }
    }

    public function testPermisosDelEncargado(): void
    {
        $token = $this->token($this->insertUser('ENCARGADO', 'encargado.test'));
        $this->authenticate($token, 'purchases.create');
        $this->authenticate($token, 'expenses.create');
        $this->authenticate($token, 'reports.read');
        foreach (['orders.create', 'orders.read', 'payments.create', 'users.manage', 'catalog.manage', 'expense_categories.manage'] as $denied) {
            $this->assertApiError('FORBIDDEN', 403, fn () => $this->authenticate($token, $denied));
        }
    }

    public function testAdminTieneTodosLosPermisos(): void
    {
        $token = $this->token($this->insertUser('ADMIN', 'admin.test'));
        foreach ($this->db->query('SELECT code FROM permissions')->fetchAll(PDO::FETCH_COLUMN) as $permission) {
            $this->authenticate($token, $permission);
        }
    }

    public function testRutaDeSesionAceptaCualquierRol(): void
    {
        $user = $this->authenticate($this->token($this->insertUser('ENCARGADO', 'encargado.test')), Router::SESSION);
        $this->assertSame('ENCARGADO', $user->roleCode);
    }

    public function testQuitarUnPermisoRigeAlInstante(): void
    {
        $token = $this->token($this->insertUser('CAJERO', 'cajero.test'));
        $this->authenticate($token, 'orders.create');
        $this->db->exec("DELETE FROM role_permissions
                         WHERE role_id = (SELECT id FROM roles WHERE code = 'CAJERO')
                           AND permission_id = (SELECT id FROM permissions WHERE code = 'orders.create')");
        $this->assertApiError('FORBIDDEN', 403, fn () => $this->authenticate($token, 'orders.create'));
    }

    private function token(int $userId, int $expiresIn = 900): string
    {
        $now = time();
        return Jwt::encode(['sub' => $userId, 'iat' => $now - 1, 'exp' => $now + $expiresIn], App::DEV_JWT_SECRET);
    }

    private function authenticate(?string $token, string $permission): AuthUser
    {
        return AuthMiddleware::authenticate($this->db, $token, $permission, App::DEV_JWT_SECRET, time());
    }
}
