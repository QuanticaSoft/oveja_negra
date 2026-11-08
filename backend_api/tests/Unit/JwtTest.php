<?php

declare(strict_types=1);

final class JwtTest extends TestCase
{
    private const SECRET = 'test-secret-de-al-menos-sesenta-y-cuatro-caracteres-0123456789abcdef';
    private const NOW = 1_800_000_000;

    public function testIdaYVuelta(): void
    {
        $token = Jwt::encode(['sub' => 7, 'iat' => self::NOW, 'exp' => self::NOW + 900], self::SECRET);
        $this->assertSame(7, Jwt::decode($token, self::SECRET, self::NOW)['sub']);
    }

    public function testFirmaAlterada(): void
    {
        $token = $this->validToken();
        $tampered = substr($token, 0, -2) . (str_ends_with($token, 'AA') ? 'BB' : 'AA');
        $this->assertRejected($tampered);
    }

    public function testPayloadAlteradoConservandoLaFirma(): void
    {
        [$header, , $signature] = explode('.', $this->validToken());
        $payload = Jwt::base64UrlEncode(json_encode(['sub' => 1, 'iat' => self::NOW, 'exp' => self::NOW + 900]));
        $this->assertRejected("{$header}.{$payload}.{$signature}");
    }

    public function testOtroSecretoNoValida(): void
    {
        $this->assertThrows(InvalidArgumentException::class,
            fn () => Jwt::decode($this->validToken(), self::SECRET . 'x', self::NOW));
    }

    public function testAlgNoneRechazado(): void
    {
        $header = Jwt::base64UrlEncode(json_encode(['alg' => 'none', 'typ' => 'JWT']));
        $payload = Jwt::base64UrlEncode(json_encode(['sub' => 7, 'iat' => self::NOW, 'exp' => self::NOW + 900]));
        $this->assertRejected("{$header}.{$payload}.");
    }

    public function testOtroAlgoritmoConFirmaValidaRechazado(): void
    {
        // Firma HS256 correcta, pero el header dice HS512: no es el header que emitimos.
        $header = Jwt::base64UrlEncode(json_encode(['alg' => 'HS512', 'typ' => 'JWT']));
        $payload = Jwt::base64UrlEncode(json_encode(['sub' => 7, 'iat' => self::NOW, 'exp' => self::NOW + 900]));
        $signature = Jwt::base64UrlEncode(hash_hmac('sha256', "{$header}.{$payload}", self::SECRET, true));
        $this->assertRejected("{$header}.{$payload}.{$signature}");
    }

    public function testExpirado(): void
    {
        $token = Jwt::encode(['sub' => 7, 'iat' => self::NOW - 1000, 'exp' => self::NOW], self::SECRET);
        $this->assertRejected($token);
    }

    public function testEmitidoEnElFuturo(): void
    {
        $token = Jwt::encode(['sub' => 7, 'iat' => self::NOW + 3600, 'exp' => self::NOW + 7200], self::SECRET);
        $this->assertRejected($token);
    }

    public function testSinExpRechazado(): void
    {
        $this->assertRejected(Jwt::encode(['sub' => 7, 'iat' => self::NOW], self::SECRET));
    }

    public function testFormatosRotos(): void
    {
        foreach (['', 'abc', 'a.b', 'a.b.c.d', '!!.??.**'] as $token) {
            $this->assertRejected($token);
        }
    }

    private function validToken(): string
    {
        return Jwt::encode(['sub' => 7, 'iat' => self::NOW, 'exp' => self::NOW + 900], self::SECRET);
    }

    private function assertRejected(string $token): void
    {
        $this->assertThrows(InvalidArgumentException::class, fn () => Jwt::decode($token, self::SECRET, self::NOW));
    }
}
