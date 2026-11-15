<?php

declare(strict_types=1);

final class PaymentSettingsTest extends DbTestCase
{
    private string $mediaDir;
    private PaymentSettingsService $settings;

    public function setUp(): void
    {
        parent::setUp();
        $this->mediaDir = sys_get_temp_dir() . '/oveja_qr_' . bin2hex(random_bytes(4));
        mkdir($this->mediaDir);
        $admin = $this->authUser($this->insertUser('ADMIN', 'admin.test'));
        $this->settings = new PaymentSettingsService($this->db, $admin,
            new Media(['media_dir' => $this->mediaDir, 'media_base_url' => 'https://cdn.test/media']));
    }

    public function tearDown(): void
    {
        parent::tearDown();
        exec('rm -rf ' . escapeshellarg($this->mediaDir));
    }

    public function testDatosDeLaCuentaConValidacionYAuditoria(): void
    {
        $this->assertSame(['bank_name', 'account_holder', 'account_number', 'qr_url', 'updated_at'], array_keys($this->settings->get()));

        $saved = $this->settings->update(['bank_name' => ' Banco  Unión ', 'account_holder' => 'Oveja Negra SRL', 'account_number' => '']);
        $this->assertSame(['Banco Unión', 'Oveja Negra SRL', null], [$saved['bank_name'], $saved['account_holder'], $saved['account_number']]);
        $this->assertSame(1, (int) $this->scalar("SELECT count(*) FROM audit_logs WHERE entity = 'payment_settings' AND action = 'update'"));

        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->settings->update(['bank_name' => str_repeat('x', 81)]));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->settings->update([]));
        // Una sola fila: la BD no deja crear otra ni borrarla.
        $this->assertDbRejects('23514', 'INSERT INTO payment_settings (id) VALUES (2)');
        $this->assertDbRejects('23001', 'DELETE FROM payment_settings');
    }

    public function testQrSeGuardaEnPngYReemplazaAlAnterior(): void
    {
        $first = $this->settings->replaceQr($this->qrImage());
        $this->assertTrue(str_starts_with($first['qr_url'], 'https://cdn.test/media/qr/'));
        $this->assertTrue(str_ends_with($first['qr_url'], '.png'), 'PNG sin pérdida para que se pueda escanear');
        $firstFile = $this->mediaDir . '/' . substr($first['qr_url'], strlen('https://cdn.test/media/'));
        $this->assertSame('image/png', (new finfo(FILEINFO_MIME_TYPE))->file($firstFile));

        $second = $this->settings->replaceQr($this->qrImage());
        $this->assertTrue($second['qr_url'] !== $first['qr_url']);
        $this->assertTrue(!is_file($firstFile), 'el QR anterior se borra');

        $fake = $this->mediaDir . '/no-es-imagen.png';
        file_put_contents($fake, '<?php echo "hola";');
        $this->assertApiError('UNSUPPORTED_IMAGE', 415, fn () => $this->settings->replaceQr($fake));
    }

    private function qrImage(): string
    {
        $path = $this->mediaDir . '/' . bin2hex(random_bytes(4)) . '-qr.png';
        $image = imagecreatetruecolor(400, 400);
        imagefilledrectangle($image, 50, 50, 150, 150, imagecolorallocate($image, 255, 255, 255));
        imagepng($image, $path);
        return $path;
    }
}
