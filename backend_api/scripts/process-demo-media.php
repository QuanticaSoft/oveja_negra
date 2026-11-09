<?php

declare(strict_types=1);

// Procesa las fotos de seeds/media/ con el mismo ImageProcessor que usa la API y las deja en
// <media_dir>/demo/<nombre>.jpg (+ miniatura). Lo invoca seed.sh dentro del contenedor dev.
// Uso: php scripts/process-demo-media.php <media_dir>

if (PHP_SAPI !== 'cli' || !isset($argv[1])) {
    fwrite(STDERR, "Uso: php scripts/process-demo-media.php <media_dir>\n");
    exit(1);
}

require dirname(__DIR__) . '/src/bootstrap.php';

$count = 0;
foreach (glob(dirname(__DIR__) . '/seeds/media/*.jpg') as $source) {
    $path = ImageProcessor::store($source, $argv[1], 'demo', basename($source, '.jpg'));
    echo "  {$path}\n";
    $count++;
}
echo "{$count} imágenes de demo procesadas.\n";
