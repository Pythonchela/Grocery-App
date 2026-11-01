<?php

namespace App\Services\Import\Documents;

use ZipArchive;

/**
 * Reads an .xlsx workbook into tab-separated text, one block per sheet.
 *
 * An .xlsx is a zip of XML files, so this needs nothing beyond PHP's zip and
 * XML extensions. Values are read as stored: a date is its serial number and a
 * formula is its last calculated result. That is fine for a product list, where
 * the cells that matter are names, prices, sizes and stock.
 */
final class XlsxReader
{
    public const MAX_ROWS = 5000;
    public const MAX_COLUMNS = 60;

    /**
     * @return array{sheets: list<array{name: string, text: string}>, truncated: bool}
     *
     * @throws \RuntimeException when the file is not a readable workbook
     */
    public static function read(string $path): array
    {
        if (! class_exists(ZipArchive::class)) {
            throw new \RuntimeException('This server cannot open Excel files. Save the sheet as CSV and upload that instead.');
        }

        $zip = new ZipArchive();
        if ($zip->open($path) !== true) {
            throw new \RuntimeException('This does not look like an Excel (.xlsx) file.');
        }

        try {
            $workbook = $zip->getFromName('xl/workbook.xml');
            if ($workbook === false) {
                throw new \RuntimeException('This does not look like an Excel (.xlsx) file.');
            }

            $strings = self::sharedStrings($zip);
            $sheets = self::sheetFiles($zip, $workbook);

            $blocks = [];
            $truncated = false;

            foreach ($sheets as [$name, $file]) {
                $xml = $zip->getFromName($file);
                if ($xml === false) {
                    continue;
                }

                [$rows, $cut] = self::rows($xml, $strings);
                $truncated = $truncated || $cut;

                if ($rows === []) {
                    continue;
                }

                $blocks[] = ['name' => $name, 'text' => implode("\n", $rows)];
            }
        } finally {
            $zip->close();
        }

        return ['sheets' => $blocks, 'truncated' => $truncated];
    }

    /** @return list<string> */
    private static function sharedStrings(ZipArchive $zip): array
    {
        $xml = $zip->getFromName('xl/sharedStrings.xml');
        if ($xml === false) {
            return [];
        }

        $doc = self::load($xml);
        $out = [];

        foreach ($doc->si ?? [] as $si) {
            // A string is either one <t> or several rich-text runs <r><t>.
            $text = '';
            if (isset($si->t)) {
                $text = (string) $si->t;
            }
            foreach ($si->r ?? [] as $run) {
                $text .= (string) $run->t;
            }
            $out[] = $text;
        }

        return $out;
    }

    /** @return list<array{0: string, 1: string}> [sheet name, path inside the zip] */
    private static function sheetFiles(ZipArchive $zip, string $workbookXml): array
    {
        $workbook = self::load($workbookXml);
        $rels = [];

        $relsXml = $zip->getFromName('xl/_rels/workbook.xml.rels');
        if ($relsXml !== false) {
            foreach (self::load($relsXml)->Relationship ?? [] as $rel) {
                $rels[(string) $rel['Id']] = (string) $rel['Target'];
            }
        }

        $out = [];
        $position = 0;

        foreach ($workbook->sheets->sheet ?? [] as $sheet) {
            $position++;
            $attributes = $sheet->attributes('http://schemas.openxmlformats.org/officeDocument/2006/relationships');
            $target = $rels[(string) ($attributes['id'] ?? '')] ?? "worksheets/sheet{$position}.xml";
            $target = ltrim($target, '/');
            $out[] = [(string) $sheet['name'], str_starts_with($target, 'xl/') ? $target : 'xl/'.$target];
        }

        return $out;
    }

    /**
     * @param  list<string>  $strings
     * @return array{0: list<string>, 1: bool} tab-separated rows, and whether a cap cut the sheet short
     */
    private static function rows(string $xml, array $strings): array
    {
        $doc = self::load($xml);
        $lines = [];
        $cut = false;

        foreach ($doc->sheetData->row ?? [] as $row) {
            if (count($lines) >= self::MAX_ROWS) {
                $cut = true;
                break;
            }

            $cells = [];
            $widest = 0;

            foreach ($row->c ?? [] as $cell) {
                $column = self::columnIndex((string) $cell['r']);
                if ($column >= self::MAX_COLUMNS) {
                    continue;
                }

                $cells[$column] = self::cellValue($cell, $strings);
                $widest = max($widest, $column + 1);
            }

            if ($widest === 0) {
                continue;
            }

            $line = [];
            for ($i = 0; $i < $widest; $i++) {
                $line[] = $cells[$i] ?? '';
            }

            $text = implode("\t", $line);
            if (trim($text, "\t ") !== '') {
                $lines[] = $text;
            }
        }

        return [$lines, $cut];
    }

    private static function cellValue(\SimpleXMLElement $cell, array $strings): string
    {
        $type = (string) $cell['t'];

        $value = match ($type) {
            's' => $strings[(int) $cell->v] ?? '',
            'inlineStr' => (string) ($cell->is->t ?? ''),
            'b' => (string) $cell->v === '1' ? 'Yes' : 'No',
            default => (string) $cell->v,
        };

        // A tab or line break inside a cell would break the row apart.
        $value = trim(preg_replace('/\s+/u', ' ', $value) ?? '');

        // 1499.0000000001 from a spreadsheet's floating point arithmetic.
        if ($type === '' && is_numeric($value) && str_contains($value, '.')) {
            $value = rtrim(rtrim(number_format((float) $value, 4, '.', ''), '0'), '.');
        }

        return $value;
    }

    /** "C7" is column 2. */
    private static function columnIndex(string $reference): int
    {
        preg_match('/^[A-Z]+/i', $reference, $m);
        $letters = strtoupper($m[0] ?? 'A');
        $index = 0;

        foreach (str_split($letters) as $ch) {
            $index = $index * 26 + (ord($ch) - 64);
        }

        return max(0, $index - 1);
    }

    private static function load(string $xml): \SimpleXMLElement
    {
        $previous = libxml_use_internal_errors(true);
        // NONET: a workbook must never make the server fetch anything.
        $doc = simplexml_load_string($xml, \SimpleXMLElement::class, LIBXML_NONET);
        libxml_use_internal_errors($previous);

        if ($doc === false) {
            throw new \RuntimeException('This Excel file is damaged or not a real .xlsx.');
        }

        return $doc;
    }
}
