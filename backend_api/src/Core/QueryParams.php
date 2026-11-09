<?php

declare(strict_types=1);

final class QueryParams
{
    /**
     * Los parámetros de query presentes y no vacíos, solo los nombrados.
     *
     * @param list<string> $names
     * @return array<string, string>
     */
    public static function only(array $names): array
    {
        $query = [];
        foreach ($names as $name) {
            $value = Request::query($name);
            if ($value !== null) {
                $query[$name] = $value;
            }
        }
        return $query;
    }
}
