<?php

declare(strict_types=1);

/**
 * Datos de la cuenta del negocio y QR de cobro (una sola fila). El QR lo genera el banco: aquí solo
 * se guarda su imagen, en PNG sin pérdida para que se pueda escanear.
 */
final class PaymentSettingsService
{
    private const UPLOAD_PREFIX = 'qr/';
    private const TEXT_FIELDS = ['bank_name' => 80, 'account_holder' => 120, 'account_number' => 40];

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor, private readonly Media $media)
    {
    }

    public function get(): array
    {
        return $this->toPublic($this->row());
    }

    public function update(array $input): array
    {
        $fields = [];
        $errors = [];
        foreach (self::TEXT_FIELDS as $field => $max) {
            if (array_key_exists($field, $input)) {
                $value = Validation::optionalText($input[$field], $max);
                if ($value === false) {
                    $errors[$field] = "Máximo {$max} caracteres.";
                } else {
                    $fields[$field] = $value;
                }
            }
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($fields === []) {
            throw ApiException::validation([], 'No hay campos para actualizar.');
        }

        return Db::transaction($this->db, function () use ($fields): array {
            $before = $this->row(forUpdate: true);
            $set = implode(', ', array_map(static fn (string $column): string => "{$column} = ?", array_keys($fields)));
            $this->db->prepare("UPDATE payment_settings SET {$set}, updated_by = ? WHERE id = 1")
                ->execute([...array_values($fields), $this->actor->id]);
            Audit::log($this->db, $this->actor->id, 'payment_settings', 1, 'update',
                array_intersect_key($before, $fields), $fields);
            return $this->get();
        });
    }

    /** Guarda el QR nuevo y recién después de confirmar en la BD borra el anterior. */
    public function replaceQr(string $sourcePath): array
    {
        $newPath = ImageProcessor::storePng($sourcePath, $this->media->dir(), self::UPLOAD_PREFIX . date('Y/m'));
        try {
            $oldPath = Db::transaction($this->db, function () use ($newPath): ?string {
                $before = $this->row(forUpdate: true);
                $this->db->prepare('UPDATE payment_settings SET qr_image_path = ?, updated_by = ? WHERE id = 1')
                    ->execute([$newPath, $this->actor->id]);
                Audit::log($this->db, $this->actor->id, 'payment_settings', 1, 'replace_qr',
                    ['qr_image_path' => $before['qr_image_path']], ['qr_image_path' => $newPath]);
                return $before['qr_image_path'];
            });
        } catch (Throwable $e) {
            ImageProcessor::delete($this->media->dir(), $newPath, self::UPLOAD_PREFIX);
            throw $e;
        }
        ImageProcessor::delete($this->media->dir(), $oldPath, self::UPLOAD_PREFIX);
        return $this->get();
    }

    private function row(bool $forUpdate = false): array
    {
        $row = $this->db->query('SELECT * FROM payment_settings WHERE id = 1' . ($forUpdate ? ' FOR UPDATE' : ''))->fetch();
        if ($row === false) {
            throw new RuntimeException('Falta la fila de payment_settings (migración 008).');
        }
        return $row;
    }

    private function toPublic(array $row): array
    {
        return [
            'bank_name' => $row['bank_name'],
            'account_holder' => $row['account_holder'],
            'account_number' => $row['account_number'],
            'qr_url' => $this->media->url($row['qr_image_path']),
            'updated_at' => Dates::iso($row['updated_at']),
        ];
    }
}
