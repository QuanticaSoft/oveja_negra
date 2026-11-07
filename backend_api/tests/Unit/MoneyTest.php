<?php

declare(strict_types=1);

final class MoneyTest extends TestCase
{
    public function testToCentsAceptaHastaDosDecimales(): void
    {
        $this->assertSame(1250, Money::toCents('12.5'));
        $this->assertSame(1250, Money::toCents('12.50'));
        $this->assertSame(1200, Money::toCents('12'));
        $this->assertSame(1, Money::toCents('0.01'));
        $this->assertSame(-305, Money::toCents('-3.05'));
    }

    public function testToCentsRechazaFormatosInvalidos(): void
    {
        foreach (['12.555', '1,50', 'abc', '', '.5', '1e3'] as $invalid) {
            $this->assertThrows(InvalidArgumentException::class, fn () => Money::toCents($invalid));
        }
    }

    public function testFromCentsDevuelveFormatoNumeric(): void
    {
        $this->assertSame('12.50', Money::fromCents(1250));
        $this->assertSame('0.05', Money::fromCents(5));
        $this->assertSame('-3.05', Money::fromCents(-305));
    }

    public function testSumaEnCentavosEsExacta(): void
    {
        // 0.1 + 0.2 en float da 0.30000000000000004.
        $this->assertSame('0.30', Money::fromCents(Money::toCents('0.1') + Money::toCents('0.2')));
    }

    public function testBobFormatoBoliviano(): void
    {
        $this->assertSame('Bs 3.480', Money::bob(348000));
        $this->assertSame('Bs 1.250,50', Money::bob(125050));
        $this->assertSame('Bs 0,05', Money::bob(5));
    }
}
