<?php

declare(strict_types=1);

final class RolesServiceTest extends DbTestCase
{
    private RolesService $service;

    public function setUp(): void
    {
        parent::setUp();
        $this->service = new RolesService($this->db, $this->authUser($this->insertUser('ADMIN', 'admin.test')));
    }

    public function testListaRolesConPermisos(): void
    {
        $byCode = array_column($this->service->list(), null, 'code');
        $this->assertSame(['ADMIN', 'CAJERO', 'ENCARGADO'], array_keys($byCode));
        $this->assertTrue(in_array('orders.create', $byCode['CAJERO']['permissions'], true));
        $this->assertSame(28, count($this->service->permissions()));
    }

    public function testReemplazarPermisosQuedaAuditado(): void
    {
        $roleId = $this->roleId('CAJERO');
        $role = $this->service->replacePermissions($roleId, ['permissions' => ['catalog.read', 'orders.read', 'catalog.read']]);
        $this->assertSame(['catalog.read', 'orders.read'], $role['permissions']);
        $this->assertSame(1, (int) $this->scalar(
            "SELECT count(*) FROM audit_logs WHERE entity = 'roles' AND entity_id = ? AND action = 'replace_permissions'", [$roleId]));
    }

    public function testCodigosDesconocidosOFormatoInvalido(): void
    {
        $roleId = $this->roleId('CAJERO');
        $e = $this->assertApiError('VALIDATION_ERROR', 400,
            fn () => $this->service->replacePermissions($roleId, ['permissions' => ['catalog.read', 'hacer.magia']]));
        $this->assertTrue(str_contains($e->details['permissions'], 'hacer.magia'));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->service->replacePermissions($roleId, ['permissions' => 'catalog.read']));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->service->replacePermissions($roleId, ['permissions' => [1, 2]]));
    }

    public function testAdminConservaLosPermisosDeAdministracion(): void
    {
        $this->assertApiError('ADMIN_PERMISSIONS_REQUIRED', 409,
            fn () => $this->service->replacePermissions($this->roleId('ADMIN'), ['permissions' => ['users.manage']]));
        $this->assertApiError('NOT_FOUND', 404, fn () => $this->service->replacePermissions(999999, ['permissions' => []]));
    }

    private function roleId(string $code): int
    {
        return (int) $this->scalar('SELECT id FROM roles WHERE code = ?', [$code]);
    }
}
