<?php

declare(strict_types=1);

/**
 * Importes en bolivianos como enteros en centavos. Nunca float: flamenco no tiene
 * bcmath y un float acumula errores de redondeo en totales.
 */
final class Money
{
    /** "12.5" | "12.50" | "-3" → centavos. Lanza si no es un decimal con hasta 2 decimales. */
    public static function toCents(string $amount): int
    {
        if (!preg_match('/^(-)?(\d{1,10})(?:\.(\d{1,2}))?$/', $amount, $m)) {
            throw new InvalidArgumentException("Importe inválido: {$amount}");
        }
        $cents = (int) $m[2] * 100 + (int) str_pad($m[3] ?? '0', 2, '0');
        return $m[1] === '-' ? -$cents : $cents;
    }

    /** Centavos → "12.50", el formato que espera una columna NUMERIC(12,2). */
    public static function fromCents(int $cents): string
    {
        $sign = $cents < 0 ? '-' : '';
        $abs = abs($cents);
        return sprintf('%s%d.%02d', $sign, intdiv($abs, 100), $abs % 100);
    }

    /** Mismo formato que la app: "Bs 3.480" o "Bs 1.250,50". */
    public static function bob(int $cents): string
    {
        $sign = $cents < 0 ? '-' : '';
        $abs = abs($cents);
        $whole = number_format(intdiv($abs, 100), 0, ',', '.');
        $fraction = $abs % 100;
        return $fraction === 0
            ? "Bs {$sign}{$whole}"
            : sprintf('Bs %s%s,%02d', $sign, $whole, $fraction);
    }
}
