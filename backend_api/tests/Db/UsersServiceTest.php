<?php

declare(strict_types=1);

final class UsersServiceTest extends DbTestCase
{
    private int $adminId;
    private UsersService $service;

    public function setUp(): void
    {
        parent::setUp();
        $this->adminId = $this->insertUser('ADMIN', 'admin.test');
        $this->service = new UsersService($this->db, $this->authUser($this->adminId));
    }

    public function testAltaDeUsuarioAuditadaSinHash(): void
    {
        $user = $this->service->create([
            'username' => 'Nuevo.Cajero', 'full_name' => 'Nuevo Cajero', 'phone' => '+59170000002',
            'role_code' => 'cajero', 'password' => 'clave-segura-1',
        ]);
        $this->assertSame('nuevo.cajero', $user['username']);
        $this->assertSame('CAJERO', $user['role']);
        $this->assertTrue(!array_key_exists('password_hash', $user));

        $audit = $this->scalar("SELECT after::text FROM audit_logs WHERE entity = 'users' AND entity_id = ? AND action = 'create'", [$user['id']]);
        $this->assertTrue(str_contains($audit, 'nuevo.cajero'));
        $this->assertTrue(!str_contains($audit, 'password'));
        $this->assertTrue(Passwords::verify('clave-segura-1', (new UserRepository($this->db))->findPasswordHash($user['id'])));
    }

    public function testAltaValidaCampos(): void
    {
        $e = $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->service->create([
            'username' => 'a b', 'full_name' => '', 'phone' => '777', 'role_code' => 'JEFE', 'password' => 'corta',
        ]));
        $this->assertSame(['full_name', 'password', 'phone', 'role_code', 'username'], $this->sortedKeys($e->details));
    }

    public function testUsuarioYCelularDuplicados(): void
    {
        $this->insertUser('CAJERO', 'repetido', '+59170000003');
        $base = ['full_name' => 'X', 'role_code' => 'CAJERO', 'password' => 'clave-segura-1'];
        $this->assertApiError('USERNAME_TAKEN', 409, fn () => $this->service->create($base + ['username' => 'repetido']));
        $this->assertApiError('PHONE_TAKEN', 409,
            fn () => $this->service->create($base + ['username' => 'otro', 'phone' => '+59170000003']));
    }

    public function testDesactivarRevocaSesionesYReactivar(): void
    {
        $id = $this->insertUser('CAJERO', 'cajero.test');
        $tokens = new RefreshTokenRepository($this->db);
        $tokens->create($id, 3600, null);

        $this->assertSame(false, $this->service->setStatus($id, ['is_active' => false])['is_active']);
        $this->assertSame(0, $tokens->countActive($id));
        $this->assertSame(true, $this->service->setStatus($id, ['is_active' => true])['is_active']);
        $this->assertSame(2, (int) $this->scalar(
            "SELECT count(*) FROM audit_logs WHERE entity_id = ? AND action IN ('activate', 'deactivate')", [$id]));
    }

    public function testNoPuedeDesactivarseNiCambiarseElRolASiMismo(): void
    {
        $this->assertApiError('CANNOT_DEACTIVATE_SELF', 409, fn () => $this->service->setStatus($this->adminId, ['is_active' => false]));
        $this->assertApiError('CANNOT_CHANGE_OWN_ROLE', 409, fn () => $this->service->update($this->adminId, ['role_code' => 'CAJERO']));
    }

    public function testSiempreQuedaUnAdminActivo(): void
    {
        // Deja a admin.test como único ADMIN activo (la BD dev puede tener otros); el rollback lo deshace.
        $this->db->prepare("UPDATE users SET is_active = false
                            WHERE id <> ? AND role_id = (SELECT id FROM roles WHERE code = 'ADMIN')")->execute([$this->adminId]);
        $actor = $this->authUser($this->insertUser('ADMIN', 'otro.admin'));
        $this->db->prepare('UPDATE users SET is_active = false WHERE id = ?')->execute([$actor->id]);
        $service = new UsersService($this->db, $actor);

        $this->assertApiError('LAST_ADMIN', 409, fn () => $service->setStatus($this->adminId, ['is_active' => false]));
        $this->assertApiError('LAST_ADMIN', 409, fn () => $service->update($this->adminId, ['role_code' => 'CAJERO']));
    }

    public function testActualizarYResetearPassword(): void
    {
        $id = $this->insertUser('CAJERO', 'cajero.test');
        $tokens = new RefreshTokenRepository($this->db);
        $tokens->create($id, 3600, null);

        $updated = $this->service->update($id, ['full_name' => 'Ana Pérez', 'role_code' => 'ENCARGADO', 'phone' => null]);
        $this->assertSame('Ana Pérez', $updated['full_name']);
        $this->assertSame('ENCARGADO', $updated['role']);

        $this->service->resetPassword($id, ['new_password' => 'otra-clave-1']);
        $this->assertSame(0, $tokens->countActive($id));
        $this->assertTrue(Passwords::verify('otra-clave-1', (new UserRepository($this->db))->findPasswordHash($id)));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->service->update($id, []));
        $this->assertApiError('NOT_FOUND', 404, fn () => $this->service->get(999999999));
    }

    public function testListadoPaginadoYFiltrado(): void
    {
        $this->insertUser('CAJERO', 'cajero.uno');
        $this->insertUser('CAJERO', 'cajero.dos', active: false);

        $result = $this->service->list(['role' => 'cajero', 'active' => 'true', 'per_page' => '1']);
        $this->assertSame(1, count($result['data']));
        $this->assertSame(1, $result['meta']['per_page']);
        $this->assertTrue($result['meta']['total'] >= 1);
        $this->assertSame('CAJERO', $result['data'][0]['role']);
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->service->list(['per_page' => '500']));
    }

    private function sortedKeys(array $data): array
    {
        $keys = array_keys($data);
        sort($keys);
        return $keys;
    }
}
