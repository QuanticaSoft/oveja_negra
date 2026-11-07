<?php

declare(strict_types=1);

final class ValidationTest extends TestCase
{
    public function testMoneyAceptaStringEnteroYFloatDeJson(): void
    {
        $this->assertSame(1250, Validation::money('12.50'));
        $this->assertSame(1200, Validation::money(12));
        $this->assertSame(1250, Validation::money(json_decode('12.5')));
        $this->assertSame(10, Validation::money(json_decode('0.1')));
    }

    public function testMoneyRechazaNegativosYMasDeDosDecimales(): void
    {
        $this->assertNull(Validation::money('-1'));
        $this->assertNull(Validation::money(-1));
        $this->assertNull(Validation::money('12.555'));
        $this->assertNull(Validation::money(12.555));
        $this->assertNull(Validation::money(null));
        $this->assertNull(Validation::money(true));
    }

    public function testPhoneFormatoBolivia(): void
    {
        $this->assertSame('+59171234567', Validation::phone('+59171234567'));
        $this->assertNull(Validation::phone('71234567'));
        $this->assertNull(Validation::phone('+5917123456'));
    }

    public function testTextNormalizaEspaciosYLongitud(): void
    {
        $this->assertSame('Doble queso', Validation::text("  Doble   queso ", 20));
        $this->assertNull(Validation::text('   ', 20));
        $this->assertNull(Validation::text(str_repeat('a', 21), 20));
        $this->assertSame(false, Validation::optionalText(str_repeat('a', 21), 20));
        $this->assertNull(Validation::optionalText('', 20));
    }

    public function testPasswordEntre8Y72Bytes(): void
    {
        $this->assertNull(Validation::password('1234567'));
        $this->assertSame('12345678', Validation::password('12345678'));
        $this->assertSame(str_repeat('a', 72), Validation::password(str_repeat('a', 72)));
        $this->assertNull(Validation::password(str_repeat('a', 73)));
        // "ñ" ocupa 2 bytes: 36 caben en los 72 bytes de bcrypt, 37 no.
        $this->assertSame(str_repeat('ñ', 36), Validation::password(str_repeat('ñ', 36)));
        $this->assertNull(Validation::password(str_repeat('ñ', 37)));
        $this->assertNull(Validation::password(12345678));
    }

    public function testUsernameSeNormalizaAMinusculas(): void
    {
        $this->assertSame('ana.perez', Validation::username(' Ana.Perez '));
        $this->assertNull(Validation::username('ab'));
        $this->assertNull(Validation::username('ana perez'));
        $this->assertNull(Validation::username('añá'));
    }

    public function testPositiveInt(): void
    {
        $this->assertSame(5, Validation::positiveInt('5'));
        $this->assertSame(5, Validation::positiveInt(5));
        $this->assertNull(Validation::positiveInt('0'));
        $this->assertNull(Validation::positiveInt('05'));
        $this->assertNull(Validation::positiveInt(-3));
    }
}
