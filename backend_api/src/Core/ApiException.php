<?php

declare(strict_types=1);

/** Error esperado que se devuelve tal cual al cliente. */
final class ApiException extends RuntimeException
{
    public function __construct(
        public readonly string $errorCode,
        string $message,
        public readonly int $status = 400,
        public readonly array $details = [],
    ) {
        parent::__construct($message);
    }

    public static function validation(array $details, string $message = 'Datos inválidos.'): self
    {
        return new self('VALIDATION_ERROR', $message, 400, $details);
    }

    public static function notFound(string $message = 'No encontrado.'): self
    {
        return new self('NOT_FOUND', $message, 404);
    }

    public static function conflict(string $errorCode, string $message): self
    {
        return new self($errorCode, $message, 409);
    }
}
