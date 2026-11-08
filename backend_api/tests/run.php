<?php

declare(strict_types=1);

// Runner mínimo sin dependencias (flamenco no tiene composer). Cada archivo
// tests/**/<Nombre>Test.php define la clase <Nombre>Test con métodos test*.
// Uso: php tests/run.php [filtro]   (el filtro se busca en "Archivo::metodo")

require dirname(__DIR__) . '/src/bootstrap.php';
require __DIR__ . '/TestCase.php';

// Algunos tests provocan a propósito eventos que la API registra (p. ej. reuso de refresh token).
$logFile = sys_get_temp_dir() . '/oveja_negra_tests.log';
ini_set('error_log', $logFile);

$filter = $argv[1] ?? '';
$files = new RecursiveIteratorIterator(new RecursiveDirectoryIterator(__DIR__, FilesystemIterator::SKIP_DOTS));
$testFiles = [];
foreach ($files as $file) {
    if (str_ends_with($file->getFilename(), 'Test.php')) {
        $testFiles[] = $file->getPathname();
    }
}
sort($testFiles);

$passed = 0;
$failures = [];
foreach ($testFiles as $path) {
    require $path;
    $class = basename($path, '.php');
    foreach (get_class_methods($class) as $method) {
        $name = "{$class}::{$method}";
        if (!str_starts_with($method, 'test') || ($filter !== '' && !str_contains($name, $filter))) {
            continue;
        }
        $test = new $class();
        try {
            $test->setUp();
            $test->$method();
            $passed++;
            echo '.';
        } catch (Throwable $e) {
            $failures[] = [$name, $e];
            echo 'F';
        } finally {
            $test->tearDown();
        }
    }
}

echo PHP_EOL . PHP_EOL;
foreach ($failures as [$name, $e]) {
    $kind = $e instanceof AssertionFailed ? 'FALLO' : 'ERROR ' . $e::class;
    echo "✗ {$name}\n  {$kind}: {$e->getMessage()}\n";
    if (!$e instanceof AssertionFailed) {
        echo "  en {$e->getFile()}:{$e->getLine()}\n";
    }
}
printf("%d OK, %d fallidos (error_log de la API: %s)\n", $passed, count($failures), $logFile);
exit($failures === [] ? 0 : 1);
