<?php

declare(strict_types=1);

final class Dates
{
    /** Timestamp de Postgres → ISO 8601 con zona ("2026-11-07T21:30:00-04:00"). */
    public static function iso(?string $timestamp): ?string
    {
        return $timestamp === null ? null : (new DateTimeImmutable($timestamp))->format(DATE_ATOM);
    }
}
