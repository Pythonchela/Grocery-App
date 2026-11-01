<?php

namespace App\Services\Import;

/**
 * Turns the AI's records into review rows, through exactly the same
 * normalisation, category matching and validation as a pasted spreadsheet.
 */
class ImportRowFactory extends HeuristicProductParser
{
    /**
     * @param  list<array>  $records
     * @param  list<array>  $categories  [['id', 'name', 'slug'], ...]
     * @return list<array>
     */
    public function rows(array $records, array $categories, int $defaultStock = 10): array
    {
        $this->defaultStock = max(0, $defaultStock);
        $rows = [];

        foreach (array_values($records) as $i => $record) {
            $rows[] = $this->normaliseRow($record, $i, $categories);
        }

        return $rows;
    }

    protected function driverName(): string
    {
        return 'ai';
    }
}
