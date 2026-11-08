<?php

declare(strict_types=1);

final class Db
{
    private static ?PDO $pdo = null;

    public static function connect(array $dbConfig): PDO
    {
        if (self::$pdo !== null) {
            return self::$pdo;
        }

        $schema = $dbConfig['schema'];
        // El schema se interpola en SQL: solo se aceptan los nuestros. Esto
        // también impide apuntar por error a "public" u otro schema de gyros.
        if (!preg_match('/^oveja_negra(_staging)?$/', $schema)) {
            throw new RuntimeException('Schema no permitido.');
        }

        $pdo = new PDO($dbConfig['dsn'], $dbConfig['user'], $dbConfig['password'], [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
        $pdo->exec("SET search_path TO {$schema}");
        $pdo->exec("SET TIME ZONE 'America/La_Paz'");
        // La instancia es compartida con gyros (producción): ninguna consulta nuestra debe acapararla.
        $pdo->prepare('SELECT set_config(\'statement_timeout\', ?, false)')
            ->execute([$dbConfig['statement_timeout'] ?? '10s']);

        return self::$pdo = $pdo;
    }

    private static int $savepointDepth = 0;

    /**
     * Ejecuta $work dentro de una transacción; si lanza, hace rollback y relanza.
     * Si ya hay una transacción abierta (p. ej. un test con rollback) usa un savepoint.
     *
     * @template T
     * @param callable(PDO): T $work
     * @return T
     */
    public static function transaction(PDO $pdo, callable $work): mixed
    {
        if ($pdo->inTransaction()) {
            $savepoint = 'sp_' . ++self::$savepointDepth;
            $pdo->exec("SAVEPOINT {$savepoint}");
            try {
                $result = $work($pdo);
                $pdo->exec("RELEASE SAVEPOINT {$savepoint}");
                return $result;
            } catch (Throwable $e) {
                $pdo->exec("ROLLBACK TO SAVEPOINT {$savepoint}");
                throw $e;
            } finally {
                self::$savepointDepth--;
            }
        }

        $pdo->beginTransaction();
        try {
            $result = $work($pdo);
            $pdo->commit();
            return $result;
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
    }
}
