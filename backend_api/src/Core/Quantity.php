<?php

declare(strict_types=1);

/** Cantidades de insumo (NUMERIC(12,3)) como enteros en milésimas, igual que Money con los centavos. */
final class Quantity
{
    public static function toMilli(string $quantity): int
    {
        if (!preg_match('/^(-)?(\d{1,9})(?:\.(\d{1,3}))?$/', $quantity, $m)) {
            throw new InvalidArgumentException("Cantidad inválida: {$quantity}");
        }
        $milli = (int) $m[2] * 1000 + (int) str_pad($m[3] ?? '0', 3, '0');
        return $m[1] === '-' ? -$milli : $milli;
    }

    public static function fromMilli(int $milli): string
    {
        $sign = $milli < 0 ? '-' : '';
        $abs = abs($milli);
        return sprintf('%s%d.%03d', $sign, intdiv($abs, 1000), $abs % 1000);
    }

    /** round(cantidad · precio, 2) en centavos, redondeo hacia arriba en el medio (como round() de Postgres). */
    public static function lineTotalCents(int $milli, int $unitPriceCents): int
    {
        return intdiv($milli * $unitPriceCents + 500, 1000);
    }
}
