<?php

declare(strict_types=1);

/** Proveedores: pocos registros, sin paginación. Nunca se borran; se desactivan. */
final class SuppliersService
{
    private const SELECT = 'SELECT id, name, phone, notes, is_active, created_at, updated_at FROM suppliers';

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor)
    {
    }

    public function list(array $query): array
    {
        $active = Validation::boolQuery($query['active'] ?? null, 'active');
        $stmt = $this->db->prepare(self::SELECT . ($active === null ? '' : ' WHERE is_active = ?') . ' ORDER BY name');
        $stmt->execute($active === null ? [] : [$active ? 'true' : 'false']);
        return array_map(self::toPublic(...), $stmt->fetchAll());
    }

    public function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE id = ?' . ($forUpdate ? ' FOR UPDATE' : ''));
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : self::toPublic($row);
    }

    public function create(array $input): array
    {
        $fields = self::fields($input, requireName: true);
        return $this->mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($fields): array {
            $stmt = $this->db->prepare('INSERT INTO suppliers (name, phone, notes) VALUES (?, ?, ?) RETURNING id');
            $stmt->execute([$fields['name'], $fields['phone'] ?? null, $fields['notes'] ?? null]);
            $supplier = $this->find((int) $stmt->fetchColumn());
            Audit::log($this->db, $this->actor->id, 'suppliers', $supplier['id'], 'create', null, $supplier);
            return $supplier;
        }));
    }

    public function update(int $id, array $input): array
    {
        $fields = self::fields($input, requireName: false);
        if ($fields === []) {
            throw ApiException::validation([], 'No hay campos para actualizar.');
        }
        return $this->mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($id, $fields): array {
            $before = $this->find($id, forUpdate: true) ?? throw ApiException::notFound('Proveedor no encontrado.');
            $values = array_map(static fn (mixed $v): mixed => is_bool($v) ? ($v ? 'true' : 'false') : $v, $fields);
            $set = implode(', ', array_map(static fn (string $column): string => "{$column} = ?", array_keys($values)));
            $this->db->prepare("UPDATE suppliers SET {$set} WHERE id = ?")->execute([...array_values($values), $id]);
            $after = $this->find($id);
            Audit::log($this->db, $this->actor->id, 'suppliers', $id, 'update', $before, $after);
            return $after;
        }));
    }

    /** @return array{name?: string, phone?: ?string, notes?: ?string, is_active?: bool} */
    private static function fields(array $input, bool $requireName): array
    {
        $fields = [];
        $errors = [];
        if ($requireName || array_key_exists('name', $input)) {
            $fields['name'] = Validation::text($input['name'] ?? null, 120);
            if ($fields['name'] === null) {
                $errors['name'] = 'Requerido, máximo 120 caracteres.';
            }
        }
        if (array_key_exists('phone', $input)) {
            $fields['phone'] = Validation::looseOptionalPhone($input['phone']);
            if ($fields['phone'] === false) {
                $errors['phone'] = 'Número de 7 a 15 dígitos, con "+" opcional.';
            }
        }
        if (array_key_exists('notes', $input)) {
            $fields['notes'] = Validation::optionalText($input['notes'], 500);
            if ($fields['notes'] === false) {
                $errors['notes'] = 'Máximo 500 caracteres.';
            }
        }
        if (!$requireName && array_key_exists('is_active', $input)) {
            $fields['is_active'] = Validation::bool($input['is_active']);
            if ($fields['is_active'] === null) {
                $errors['is_active'] = 'Debe ser true o false.';
            }
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        return $fields;
    }

    private static function toPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'name' => $row['name'],
            'phone' => $row['phone'],
            'notes' => $row['notes'],
            'is_active' => (bool) $row['is_active'],
            'created_at' => Dates::iso($row['created_at']),
            'updated_at' => Dates::iso($row['updated_at']),
        ];
    }

    /**
     * @template T
     * @param callable(): T $work
     * @return T
     */
    private function mapDuplicateName(callable $work): mixed
    {
        try {
            return $work();
        } catch (PDOException $e) {
            if (Db::isUniqueViolation($e, 'uq_suppliers_name')) {
                throw ApiException::conflict('SUPPLIER_NAME_TAKEN', 'Ya existe un proveedor con ese nombre.');
            }
            throw $e;
        }
    }
}
