<?php

declare(strict_types=1);

// En flamenco deploy.sh genera app_root.php apuntando al código fuera del
// docroot (~/oveja_negra/<env>); en dev el código está junto a public/.
$appRoot = is_file(__DIR__ . '/app_root.php') ? require __DIR__ . '/app_root.php' : dirname(__DIR__);

require $appRoot . '/src/bootstrap.php';

App::run();
