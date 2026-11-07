<?php

declare(strict_types=1);

final class ErrorHandler
{
    public static function register(): void
    {
        // Un warning a mitad de una operación no debe dejar datos a medias: se trata como excepción.
        set_error_handler(static function (int $severity, string $message, string $file, int $line): bool {
            throw new ErrorException($message, 0, $severity, $file, $line);
        });

        set_exception_handler(static function (Throwable $e): void {
            if ($e instanceof ApiException) {
                Response::error($e->errorCode, $e->getMessage(), $e->status, $e->details);
            }
            error_log('[oveja_negra] ' . $e::class . ': ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
            Response::error('INTERNAL_ERROR', 'Error interno.', 500);
        });
    }
}
