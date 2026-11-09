<?php

declare(strict_types=1);

final class QuantityTest extends TestCase
{
    public function testMilesimasIdaYVuelta(): void
    {
        $this->assertSame(1500, Quantity::toMilli('1.5'));
        $this->assertSame(-250, Quantity::toMilli('-0.25'));
        $this->assertSame('1.500', Quantity::fromMilli(1500));
        $this->assertSame('-0.005', Quantity::fromMilli(-5));
        $this->assertThrows(InvalidArgumentException::class, fn () => Quantity::toMilli('1.2345'));
    }

    public function testTotalDeLineaRedondeaIgualQuePostgres(): void
    {
        $this->assertSame(335, Quantity::lineTotalCents(333, 1005));   // 3.34665 → 3.35
        $this->assertSame(1, Quantity::lineTotalCents(1, 500));        // 0.005 → 0.01 (mitad hacia arriba)
        $this->assertSame(0, Quantity::lineTotalCents(1, 499));
        $this->assertSame(15000, Quantity::lineTotalCents(2500, 6000));
    }

    public function testValidacionDeCantidad(): void
    {
        $this->assertSame(1500, Validation::quantity(1.5));
        $this->assertSame(2000, Validation::quantity('2'));
        $this->assertSame(-250, Validation::quantity('-0.25', signed: true));
        foreach ([0, '0.000', '-1', '1.2345', 'abc', null, '100000'] as $invalid) {
            $this->assertNull(Validation::quantity($invalid));
        }
        $this->assertNull(Validation::quantity(0, signed: true));
    }

    public function testFechasYRango(): void
    {
        $this->assertSame('2026-02-28', Validation::date('2026-02-28'));
        $this->assertNull(Validation::date('2026-02-29'));
        $this->assertNull(Validation::date('08/11/2026'));
        $range = DateRange::fromQuery([], '2026-11-01', '2026-11-08');
        $this->assertSame(['2026-11-01', '2026-11-08'], [$range->from, $range->to]);
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => DateRange::fromQuery(['from' => '2026-11-09'], '2026-11-01', '2026-11-08'));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => DateRange::fromQuery(['from' => '2026-01-01'], '2026-11-01', '2026-11-08'));
    }

    public function testTelefonoFlexible(): void
    {
        $this->assertSame('+59170000000', Validation::looseOptionalPhone('+591 7000-0000'));
        $this->assertSame('5491112345678', Validation::looseOptionalPhone('549 11 1234 5678'));
        $this->assertNull(Validation::looseOptionalPhone(''));
        $this->assertSame(false, Validation::looseOptionalPhone('123'));
        $this->assertSame(false, Validation::looseOptionalPhone(70000000));
    }
}
