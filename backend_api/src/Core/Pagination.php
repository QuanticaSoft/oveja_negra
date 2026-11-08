<?php

declare(strict_types=1);

final class Pagination
{
    private const DEFAULT_PER_PAGE = 20;
    private const MAX_PER_PAGE = 100;

    private function __construct(public readonly int $page, public readonly int $perPage)
    {
    }

    public static function fromQuery(array $query): self
    {
        $page = Validation::positiveInt($query['page'] ?? '1')
            ?? throw ApiException::validation(['page' => 'Entero positivo.']);
        $perPage = Validation::positiveInt($query['per_page'] ?? (string) self::DEFAULT_PER_PAGE);
        if ($perPage === null || $perPage > self::MAX_PER_PAGE) {
            throw ApiException::validation(['per_page' => 'Entre 1 y ' . self::MAX_PER_PAGE . '.']);
        }
        return new self($page, $perPage);
    }

    public function offset(): int
    {
        return ($this->page - 1) * $this->perPage;
    }

    public function meta(int $total): array
    {
        return ['page' => $this->page, 'per_page' => $this->perPage, 'total' => $total];
    }
}
