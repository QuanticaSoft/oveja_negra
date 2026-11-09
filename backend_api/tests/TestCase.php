<?php

declare(strict_types=1);

final class AssertionFailed extends RuntimeException
{
}

abstract class TestCase
{
    public function setUp(): void
    {
    }

    public function tearDown(): void
    {
    }

    protected function assertSame(mixed $expected, mixed $actual, string $message = ''): void
    {
        if ($expected !== $actual) {
            $this->fail(sprintf('%sSe esperaba %s y se obtuvo %s', $message ? "$message: " : '',
                var_export($expected, true), var_export($actual, true)));
        }
    }

    protected function assertTrue(bool $condition, string $message = 'Se esperaba true'): void
    {
        if (!$condition) {
            $this->fail($message);
        }
    }

    protected function assertNull(mixed $actual): void
    {
        $this->assertSame(null, $actual);
    }

    /**
     * @template E of Throwable
     * @param class-string<E> $class
     * @return E
     */
    protected function assertThrows(string $class, callable $fn): Throwable
    {
        try {
            $fn();
        } catch (Throwable $e) {
            if ($e instanceof $class) {
                return $e;
            }
            $this->fail("Se esperaba {$class} y se lanzó " . $e::class . ': ' . $e->getMessage());
        }
        $this->fail("Se esperaba {$class} y no se lanzó nada");
    }

    /** Comprueba que $fn lanza un ApiException con ese código y estado HTTP. */
    protected function assertApiError(string $errorCode, int $status, callable $fn): ApiException
    {
        $e = $this->assertThrows(ApiException::class, $fn);
        $this->assertSame($errorCode, $e->errorCode, 'Código de error');
        $this->assertSame($status, $e->status, 'Estado HTTP');
        return $e;
    }

    /** UUID v4 para Idempotency-Key. */
    protected static function uuid(): string
    {
        $hex = bin2hex(random_bytes(16));
        return sprintf('%s-%s-4%s-a%s-%s', substr($hex, 0, 8), substr($hex, 8, 4), substr($hex, 13, 3), substr($hex, 17, 3), substr($hex, 20, 12));
    }

    protected function fail(string $message): never
    {
        throw new AssertionFailed($message);
    }
}

/**
 * Cada test corre dentro de una transacción que se revierte al final: la BD dev
 * queda igual que antes de ejecutar la suite.
 */
abstract class DbTestCase extends TestCase
{
    protected PDO $db;

    public function setUp(): void
    {
        $this->db = App::db();
        $this->db->beginTransaction();
    }

    public function tearDown(): void
    {
        if ($this->db->inTransaction()) {
            $this->db->rollBack();
        }
    }

    protected const DEFAULT_PASSWORD = 'secreta123';
    // bcrypt costo 12 tarda ~0,25 s: el hash de la contraseña por defecto se calcula una vez.
    private static ?string $defaultHash = null;

    protected function insertUser(string $roleCode, string $username, ?string $phone = null, bool $active = true): int
    {
        self::$defaultHash ??= Passwords::hash(self::DEFAULT_PASSWORD);
        return (int) $this->scalar(
            'INSERT INTO users (username, full_name, phone, role_id, password_hash, is_active)
             SELECT ?, ?, ?, id, ?, ? FROM roles WHERE code = ? RETURNING id',
            [$username, "Test {$username}", $phone, self::$defaultHash, $active ? 'true' : 'false', $roleCode]);
    }

    protected function authUser(int $id): AuthUser
    {
        return (new UserRepository($this->db))->findActiveAuthUser($id) ?? $this->fail("Usuario {$id} inactivo");
    }

    /** Ejecuta SQL y devuelve la primera columna de la primera fila. */
    protected function scalar(string $sql, array $params = []): mixed
    {
        $stmt = $this->db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchColumn();
    }

    /**
     * Comprueba que Postgres rechaza la sentencia con el SQLSTATE indicado. Usa un
     * savepoint para que el error no aborte la transacción del test.
     */
    protected function assertDbRejects(string $sqlState, string $sql, array $params = []): void
    {
        $this->db->exec('SAVEPOINT expect_error');
        try {
            $this->db->prepare($sql)->execute($params);
        } catch (PDOException $e) {
            $this->db->exec('ROLLBACK TO SAVEPOINT expect_error');
            $this->assertSame($sqlState, $e->getCode(), 'SQLSTATE (' . $e->getMessage() . ')');
            return;
        }
        $this->db->exec('ROLLBACK TO SAVEPOINT expect_error');
        $this->fail("Se esperaba que la BD rechazara: {$sql}");
    }
}
