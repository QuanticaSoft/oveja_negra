<?php

declare(strict_types=1);

final class AuthServiceTest extends DbTestCase
{
    private const IP = '10.0.0.1';
    private const PHONE = '+59170000001';

    private AuthService $auth;
    private int $userId;

    public function setUp(): void
    {
        parent::setUp();
        $this->auth = new AuthService($this->db, App::config(), App::DEV_JWT_SECRET);
        $this->userId = $this->insertUser('CAJERO', 'cajero.test', self::PHONE);
    }

    public function testLoginPorUsuarioDevuelveSesionValida(): void
    {
        $session = $this->login('cajero.test');

        $claims = Jwt::decode($session['access_token'], App::DEV_JWT_SECRET, time());
        $this->assertSame($this->userId, $claims['sub']);
        $this->assertSame(900, $session['expires_in']);
        $this->assertTrue((bool) preg_match(RefreshTokenRepository::TOKEN_PATTERN, $session['refresh_token']));
        $this->assertSame('CAJERO', $session['user']['role']);
        $this->assertTrue(in_array('orders.create', $session['user']['permissions'], true));
        $this->assertTrue($this->scalar('SELECT last_login_at IS NOT NULL FROM users WHERE id = ?', [$this->userId]));
    }

    public function testLoginPorCelularYSinDistinguirMayusculas(): void
    {
        $this->assertSame($this->userId, $this->login(self::PHONE)['user']['id']);
        $this->assertSame($this->userId, $this->login('  CAJERO.Test ')['user']['id']);
    }

    public function testPasswordIncorrectoYUsuarioInexistenteDanElMismoError(): void
    {
        $wrong = $this->assertApiError('INVALID_CREDENTIALS', 401, fn () => $this->login('cajero.test', 'incorrecta1'));
        $missing = $this->assertApiError('INVALID_CREDENTIALS', 401, fn () => $this->login('nadie.existe'));
        $this->assertSame($wrong->getMessage(), $missing->getMessage());
    }

    public function testCuentaInactivaSoloSeRevelaConPasswordCorrecto(): void
    {
        $this->insertUser('CAJERO', 'inactivo.test', active: false);
        $this->assertApiError('USER_INACTIVE', 403, fn () => $this->login('inactivo.test'));
        $this->assertApiError('INVALID_CREDENTIALS', 401, fn () => $this->login('inactivo.test', 'incorrecta1'));
    }

    public function testBloqueoTrasCincoFallos(): void
    {
        for ($i = 0; $i < 5; $i++) {
            $this->assertApiError('INVALID_CREDENTIALS', 401, fn () => $this->login('cajero.test', 'incorrecta1'));
        }
        // Con el límite alcanzado se rechaza incluso la contraseña correcta.
        $this->assertApiError('TOO_MANY_ATTEMPTS', 429, fn () => $this->login('cajero.test'));
    }

    public function testValidaEntrada(): void
    {
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->auth->login(null, 'x', self::IP, null));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->auth->login('cajero.test', ['x'], self::IP, null));
    }

    public function testRefreshRotaYElReusoRevocaTodasLasSesiones(): void
    {
        $first = $this->login('cajero.test');
        $second = $this->auth->refresh($first['refresh_token'], null);
        $this->assertTrue($second['refresh_token'] !== $first['refresh_token']);
        $this->assertSame($this->userId, $second['user']['id']);

        // Reusar el token ya rotado = robo probable: se revoca todo, incluido el par nuevo.
        $this->assertApiError('INVALID_REFRESH_TOKEN', 401, fn () => $this->auth->refresh($first['refresh_token'], null));
        $this->assertSame(0, (new RefreshTokenRepository($this->db))->countActive($this->userId));
        $this->assertApiError('INVALID_REFRESH_TOKEN', 401, fn () => $this->auth->refresh($second['refresh_token'], null));
    }

    public function testRefreshExpiradoOInventado(): void
    {
        [, $expired] = (new RefreshTokenRepository($this->db))->create($this->userId, -1, null);
        $this->assertApiError('INVALID_REFRESH_TOKEN', 401, fn () => $this->auth->refresh($expired, null));
        $this->assertApiError('INVALID_REFRESH_TOKEN', 401,
            fn () => $this->auth->refresh(Jwt::base64UrlEncode(random_bytes(32)), null));
        $this->assertApiError('INVALID_REFRESH_TOKEN', 401, fn () => $this->auth->refresh('corto', null));
    }

    public function testRefreshDeUsuarioDesactivado(): void
    {
        $session = $this->login('cajero.test');
        $this->db->prepare('UPDATE users SET is_active = false WHERE id = ?')->execute([$this->userId]);
        $this->assertApiError('USER_INACTIVE', 401, fn () => $this->auth->refresh($session['refresh_token'], null));
    }

    public function testLogoutRevocaElRefreshToken(): void
    {
        $session = $this->login('cajero.test');
        $this->auth->logout($session['refresh_token']);
        $this->auth->logout($session['refresh_token']);
        $this->auth->logout('basura');
        $this->assertApiError('INVALID_REFRESH_TOKEN', 401, fn () => $this->auth->refresh($session['refresh_token'], null));
    }

    public function testCambioDePasswordPropia(): void
    {
        $old = $this->login('cajero.test');
        $user = $this->authUser($this->userId);

        $this->assertApiError('WRONG_PASSWORD', 400,
            fn () => $this->auth->changeOwnPassword($user, 'incorrecta1', 'nueva-clave-1', null));
        $this->assertApiError('VALIDATION_ERROR', 400,
            fn () => $this->auth->changeOwnPassword($user, self::DEFAULT_PASSWORD, 'corta', null));

        $new = $this->auth->changeOwnPassword($user, self::DEFAULT_PASSWORD, 'nueva-clave-1', null);
        $this->assertTrue($new['refresh_token'] !== $old['refresh_token']);
        $this->assertApiError('INVALID_REFRESH_TOKEN', 401, fn () => $this->auth->refresh($old['refresh_token'], null));
        $this->assertSame($this->userId, $this->login('cajero.test', 'nueva-clave-1')['user']['id']);
        $this->assertSame(1, (int) $this->scalar(
            "SELECT count(*) FROM audit_logs WHERE entity = 'users' AND entity_id = ? AND action = 'change_own_password'",
            [$this->userId]));
    }

    private function login(string $identifier, string $password = self::DEFAULT_PASSWORD): array
    {
        return $this->auth->login($identifier, $password, self::IP, 'tests');
    }
}
