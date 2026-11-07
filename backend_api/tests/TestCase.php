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
