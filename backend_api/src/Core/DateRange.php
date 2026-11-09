<?php

declare(strict_types=1);

/** Filtros from/to (YYYY-MM-DD) con rango máximo, para no cargar la BD compartida con gyros. */
final class DateRange
{
    public const MAX_DAYS = 92;

    private function __construct(public readonly string $from, public readonly string $to)
    {
    }

    public static function fromQuery(array $query, string $defaultFrom, string $defaultTo): self
    {
        $from = self::date($query['from'] ?? $defaultFrom, 'from');
        $to = self::date($query['to'] ?? $defaultTo, 'to');
        if ($from > $to) {
            throw ApiException::validation(['from' => 'Debe ser anterior o igual a "to".']);
        }
        if ((new DateTimeImmutable($from))->diff(new DateTimeImmutable($to))->days >= self::MAX_DAYS) {
            throw ApiException::validation(['to' => 'El rango máximo es de ' . self::MAX_DAYS . ' días.']);
        }
        return new self($from, $to);
    }

    public static function date(mixed $value, string $field): string
    {
        return Validation::date($value) ?? throw ApiException::validation([$field => 'Fecha YYYY-MM-DD.']);
    }
}
