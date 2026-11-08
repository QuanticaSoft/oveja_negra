<?php

declare(strict_types=1);

// Crea el PRIMER usuario ADMIN del entorno donde corre (usa su config.local.php).
// Los demás usuarios se crean desde la API. La contraseña se pide por teclado con
// eco oculto: no queda en el historial del shell, en git ni en ningún chat.
//   dev:     docker compose -f infra/docker-compose.dev.yml exec api php bin/create-admin.php
//   staging: ssh -t flamenco 'php ~/oveja_negra/staging/bin/create-admin.php'
//            (con comillas: sin ellas el Mac expande ~ a su propio home)

if (PHP_SAPI !== 'cli') {
    exit(1);
}

require dirname(__DIR__) . '/src/bootstrap.php';

// Se detecta antes de leer: con datos ya en búfer, stream_isatty() avisa de que los pierde.
define('STDIN_IS_TTY', stream_isatty(STDIN));

function ask(string $label, bool $hidden = false): string
{
    fwrite(STDOUT, $label);
    $interactive = $hidden && STDIN_IS_TTY;
    if ($interactive) {
        shell_exec('stty -echo');
    }
    $value = fgets(STDIN);
    if ($interactive) {
        shell_exec('stty echo');
        fwrite(STDOUT, PHP_EOL);
    }
    return $value === false ? '' : rtrim($value, "\r\n");
}

function fail(string $message): never
{
    fwrite(STDERR, "✗ {$message}" . PHP_EOL);
    exit(1);
}

$config = App::config();
$db = App::db();
$users = new UserRepository($db);

fwrite(STDOUT, "Entorno: {$config['env']} (schema {$config['db']['schema']})" . PHP_EOL);
if ($users->adminExists()) {
    fail('Ya existe un ADMIN en este entorno. Crea los demás usuarios desde la API.');
}

$username = Validation::username(ask('Usuario (minúsculas, 3-40): '))
    ?? fail('Usuario inválido: letras minúsculas, números, punto, guion o guion bajo.');
$fullName = Validation::text(ask('Nombre completo: '), 120) ?? fail('Nombre requerido (máx. 120).');
$password = Validation::password(ask('Contraseña (8-72 caracteres): ', hidden: true))
    ?? fail('La contraseña debe tener entre 8 y 72 caracteres.');
if (ask('Repite la contraseña: ', hidden: true) !== $password) {
    fail('Las contraseñas no coinciden.');
}

$roleId = (new RoleRepository($db))->findIdByCode('ADMIN') ?? fail('No existe el rol ADMIN: ¿faltan migraciones?');

$id = Db::transaction($db, static function () use ($db, $users, $username, $fullName, $roleId, $password): int {
    $id = $users->insert($username, $fullName, null, $roleId, Passwords::hash($password));
    Audit::log($db, null, 'users', $id, 'create_first_admin', null, $users->find($id));
    return $id;
});

fwrite(STDOUT, "✓ ADMIN '{$username}' creado (id {$id})." . PHP_EOL);
