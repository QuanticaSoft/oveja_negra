<?php

declare(strict_types=1);

/**
 * Valida y vuelve a codificar imágenes con GD. Nunca se guarda el archivo recibido:
 * se decodifica y se escribe un JPEG nuevo, así un archivo disfrazado de imagen no
 * sobrevive y se pierden los metadatos EXIF (incluida la ubicación GPS de los celulares).
 */
final class ImageProcessor
{
    public const FULL_SIDE = 800;
    public const THUMB_SIDE = 300;
    private const JPEG_QUALITY = 82;
    private const MAX_BYTES = 8 * 1024 * 1024;
    // GD necesita ~4 bytes por píxel y el pool PHP de flamenco tiene 128 MB.
    private const MAX_PIXELS = 25_000_000;
    private const THUMB_SUFFIX = '_t';

    private const DECODERS = [
        'image/jpeg' => 'imagecreatefromjpeg',
        'image/png' => 'imagecreatefrompng',
        'image/webp' => 'imagecreatefromwebp',
    ];

    /** Valida una entrada de $_FILES y devuelve la ruta del archivo temporal. */
    public static function uploadedFile(mixed $file): string
    {
        if (!is_array($file) || !is_int($file['error'] ?? null) || !is_string($file['tmp_name'] ?? null)) {
            throw ApiException::validation(['image' => 'Falta la imagen (campo "image", multipart/form-data).']);
        }
        if (in_array($file['error'], [UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE], true)) {
            throw self::tooLarge();
        }
        if ($file['error'] !== UPLOAD_ERR_OK || !is_uploaded_file($file['tmp_name'])) {
            throw new ApiException('UPLOAD_FAILED', 'No se pudo recibir la imagen. Intenta de nuevo.', 400);
        }
        return $file['tmp_name'];
    }

    /**
     * Guarda la imagen en dos tamaños y devuelve la ruta relativa del grande
     * (la miniatura es thumbPathFor() de esa ruta).
     */
    public static function store(string $sourcePath, string $mediaDir, string $relativeDir, ?string $name = null): string
    {
        if (filesize($sourcePath) > self::MAX_BYTES) {
            throw self::tooLarge();
        }
        $mime = (new finfo(FILEINFO_MIME_TYPE))->file($sourcePath);
        $info = @getimagesize($sourcePath);
        if (!isset(self::DECODERS[$mime]) || $info === false) {
            throw new ApiException('UNSUPPORTED_IMAGE', 'La imagen debe ser JPG, PNG o WEBP.', 415);
        }
        if ($info[0] * $info[1] > self::MAX_PIXELS) {
            throw new ApiException('IMAGE_TOO_LARGE', 'La imagen tiene demasiados píxeles (máx. 25 MP).', 413);
        }

        $image = @(self::DECODERS[$mime])($sourcePath);
        if ($image === false) {
            throw new ApiException('UNSUPPORTED_IMAGE', 'No se pudo leer la imagen.', 415);
        }
        if ($mime === 'image/jpeg') {
            $image = self::uprightFromExif($image, $sourcePath);
        }

        $relativeDir = trim($relativeDir, '/');
        $absoluteDir = rtrim($mediaDir, '/') . '/' . $relativeDir;
        if (!is_dir($absoluteDir) && !mkdir($absoluteDir, 0755, true) && !is_dir($absoluteDir)) {
            throw new RuntimeException("No se pudo crear {$absoluteDir}");
        }

        $relativePath = $relativeDir . '/' . ($name ?? bin2hex(random_bytes(12))) . '.jpg';
        try {
            self::writeJpeg($image, self::FULL_SIDE, rtrim($mediaDir, '/') . '/' . $relativePath);
            self::writeJpeg($image, self::THUMB_SIDE, rtrim($mediaDir, '/') . '/' . self::thumbPathFor($relativePath));
        } finally {
            imagedestroy($image);
        }
        return $relativePath;
    }

    public static function thumbPathFor(string $relativePath): string
    {
        return preg_replace('/\.jpg$/', self::THUMB_SUFFIX . '.jpg', $relativePath);
    }

    /** Borra la imagen y su miniatura, solo si están bajo $prefix (nunca la media de demo). */
    public static function delete(string $mediaDir, ?string $relativePath, string $prefix): void
    {
        if ($relativePath === null || !str_starts_with($relativePath, $prefix) || str_contains($relativePath, '..')) {
            return;
        }
        foreach ([$relativePath, self::thumbPathFor($relativePath)] as $path) {
            $absolute = rtrim($mediaDir, '/') . '/' . $path;
            if (is_file($absolute)) {
                unlink($absolute);
            }
        }
    }

    // Los celulares guardan la foto sin rotar y anotan el giro en EXIF; al re-codificar
    // esa anotación se pierde, así que el giro se aplica a los píxeles.
    private static function uprightFromExif(GdImage $image, string $sourcePath): GdImage
    {
        if (!function_exists('exif_read_data')) {
            return $image;
        }
        $exif = @exif_read_data($sourcePath);
        $angle = match (is_array($exif) ? ($exif['Orientation'] ?? 1) : 1) {
            3 => 180,
            6 => 270,
            8 => 90,
            default => 0,
        };
        if ($angle === 0) {
            return $image;
        }
        $rotated = imagerotate($image, $angle, 0);
        imagedestroy($image);
        return $rotated;
    }

    // Se escribe a un temporal y se renombra: nunca queda publicado un JPEG a medias.
    private static function writeJpeg(GdImage $source, int $maxSide, string $target): void
    {
        $width = imagesx($source);
        $height = imagesy($source);
        $scale = min(1.0, $maxSide / max($width, $height));
        $newWidth = max(1, (int) round($width * $scale));
        $newHeight = max(1, (int) round($height * $scale));

        $canvas = imagecreatetruecolor($newWidth, $newHeight);
        // Un PNG transparente quedaría negro en JPEG: se compone sobre blanco.
        imagefill($canvas, 0, 0, imagecolorallocate($canvas, 255, 255, 255));
        imagecopyresampled($canvas, $source, 0, 0, 0, 0, $newWidth, $newHeight, $width, $height);

        $temporary = $target . '.tmp';
        $written = imagejpeg($canvas, $temporary, self::JPEG_QUALITY);
        imagedestroy($canvas);
        if (!$written || !rename($temporary, $target)) {
            @unlink($temporary);
            throw new RuntimeException("No se pudo guardar {$target}");
        }
    }

    private static function tooLarge(): ApiException
    {
        return new ApiException('IMAGE_TOO_LARGE', 'La imagen supera los 8 MB.', 413);
    }
}
