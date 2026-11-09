<?php

declare(strict_types=1);

/** Dónde se guardan las imágenes y con qué URL se publican. */
final class Media
{
    public function __construct(private readonly array $config)
    {
    }

    public function dir(): string
    {
        return rtrim($this->config['media_dir'], '/');
    }

    public function url(?string $relativePath): ?string
    {
        return $relativePath === null ? null : $this->baseUrl() . '/' . ltrim($relativePath, '/');
    }

    /**
     * En staging/prod la URL viene de la config. En dev se arma con el host del request:
     * así sirve igual desde el Mac (localhost) que desde el emulador Android (10.0.2.2).
     */
    private function baseUrl(): string
    {
        if (!empty($this->config['media_base_url'])) {
            return rtrim($this->config['media_base_url'], '/');
        }
        $https = !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off';
        $host = $_SERVER['HTTP_HOST'] ?? 'localhost:8082';
        return ($https ? 'https' : 'http') . "://{$host}/media";
    }
}
