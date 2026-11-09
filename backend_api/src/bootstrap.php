<?php

declare(strict_types=1);

const API_VERSION = '0.5.0';

// Sin composer: las clases viven en src/Core/<Clase>.php o src/Modules/<Modulo>/<Clase>.php.
spl_autoload_register(static function (string $class): void {
    $coreFile = __DIR__ . "/Core/{$class}.php";
    if (is_file($coreFile)) {
        require $coreFile;
        return;
    }
    foreach (glob(__DIR__ . "/Modules/*/{$class}.php") ?: [] as $moduleFile) {
        require $moduleFile;
        return;
    }
});
