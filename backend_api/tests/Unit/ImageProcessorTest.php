<?php

declare(strict_types=1);

final class ImageProcessorTest extends TestCase
{
    private string $dir;

    public function setUp(): void
    {
        $this->dir = sys_get_temp_dir() . '/oveja_img_' . bin2hex(random_bytes(4));
        mkdir($this->dir . '/src', 0755, true);
    }

    public function tearDown(): void
    {
        exec('rm -rf ' . escapeshellarg($this->dir));
    }

    public function testJpegSeGuardaEnDosTamanos(): void
    {
        $path = ImageProcessor::store($this->jpeg(1600, 1200), $this->dir, 'p/2026/11');

        $this->assertTrue((bool) preg_match('#^p/2026/11/[0-9a-f]{24}\.jpg$#', $path), "Ruta inesperada: {$path}");
        $this->assertSame([800, 600, IMAGETYPE_JPEG], $this->dimensions($path));
        $this->assertSame([300, 225, IMAGETYPE_JPEG], $this->dimensions(ImageProcessor::thumbPathFor($path)));
    }

    public function testImagenChicaNoSeAgranda(): void
    {
        $path = ImageProcessor::store($this->jpeg(200, 100), $this->dir, 'p', 'chica');
        $this->assertSame('p/chica.jpg', $path);
        $this->assertSame([200, 100, IMAGETYPE_JPEG], $this->dimensions($path));
    }

    public function testPngTransparenteSeConvierteAJpeg(): void
    {
        $image = imagecreatetruecolor(400, 400);
        imagesavealpha($image, true);
        imagefill($image, 0, 0, imagecolorallocatealpha($image, 0, 0, 0, 127));
        $source = $this->dir . '/src/transparente.png';
        imagepng($image, $source);

        $path = ImageProcessor::store($source, $this->dir, 'p');
        $this->assertSame(IMAGETYPE_JPEG, $this->dimensions($path)[2]);
        // El fondo transparente queda blanco, no negro.
        $out = imagecreatefromjpeg($this->dir . '/' . $path);
        $this->assertTrue((imagecolorat($out, 10, 10) & 0xFF) > 240, 'El fondo debería ser blanco');
    }

    public function testArchivoQueNoEsImagenSeRechaza(): void
    {
        $fake = $this->dir . '/src/foto.jpg';
        file_put_contents($fake, "<?php echo 'hola'; ?>");
        $this->assertApiError('UNSUPPORTED_IMAGE', 415, fn () => ImageProcessor::store($fake, $this->dir, 'p'));

        $gif = $this->dir . '/src/anim.gif';
        imagegif(imagecreatetruecolor(10, 10), $gif);
        $this->assertApiError('UNSUPPORTED_IMAGE', 415, fn () => ImageProcessor::store($gif, $this->dir, 'p'));
    }

    public function testUploadSinArchivo(): void
    {
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => ImageProcessor::uploadedFile(null));
        $this->assertApiError('IMAGE_TOO_LARGE', 413,
            fn () => ImageProcessor::uploadedFile(['error' => UPLOAD_ERR_INI_SIZE, 'tmp_name' => '']));
        // Un archivo que no llegó por HTTP POST (p. ej. una ruta inventada) se rechaza.
        $this->assertApiError('UPLOAD_FAILED', 400,
            fn () => ImageProcessor::uploadedFile(['error' => UPLOAD_ERR_OK, 'tmp_name' => '/etc/passwd']));
    }

    public function testBorrarSoloDentroDelPrefijo(): void
    {
        $uploaded = ImageProcessor::store($this->jpeg(100, 100), $this->dir, 'p', 'subida');
        $demo = ImageProcessor::store($this->jpeg(100, 100), $this->dir, 'demo', 'demo');

        ImageProcessor::delete($this->dir, $demo, 'p/');
        ImageProcessor::delete($this->dir, 'p/../demo/demo.jpg', 'p/');
        $this->assertTrue(is_file("{$this->dir}/{$demo}"), 'La media de demo no se borra');

        ImageProcessor::delete($this->dir, $uploaded, 'p/');
        $this->assertTrue(!is_file("{$this->dir}/{$uploaded}") && !is_file($this->dir . '/' . ImageProcessor::thumbPathFor($uploaded)));
    }

    private function jpeg(int $width, int $height): string
    {
        $image = imagecreatetruecolor($width, $height);
        imagefill($image, 0, 0, imagecolorallocate($image, 200, 120, 40));
        $path = $this->dir . '/src/' . bin2hex(random_bytes(4)) . '.jpg';
        imagejpeg($image, $path);
        return $path;
    }

    private function dimensions(string $relativePath): array
    {
        $info = getimagesize($this->dir . '/' . $relativePath);
        return [$info[0], $info[1], $info[2]];
    }
}
