<?php

namespace App\Services\Import\Documents;

use ZipArchive;

/**
 * Reads a Word (.docx) file into plain text: paragraphs in order, list items
 * marked with a dash, and tables as one line per row with the cells joined by
 * " | " so a price list keeps its columns.
 */
final class DocxReader
{
    private const W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

    /** @throws \RuntimeException when the file is not a readable document */
    public static function read(string $path): string
    {
        if (! class_exists(ZipArchive::class)) {
            throw new \RuntimeException('This server cannot open Word files. Save the document as PDF or text and upload that instead.');
        }

        $zip = new ZipArchive();
        if ($zip->open($path) !== true) {
            throw new \RuntimeException('This does not look like a Word (.docx) file.');
        }

        $xml = $zip->getFromName('word/document.xml');
        $zip->close();

        if ($xml === false) {
            throw new \RuntimeException('This does not look like a Word (.docx) file.');
        }

        $previous = libxml_use_internal_errors(true);
        $doc = new \DOMDocument();
        // NONET: a document must never make the server fetch anything.
        $loaded = $doc->loadXML($xml, LIBXML_NONET | LIBXML_NOERROR | LIBXML_NOWARNING);
        libxml_use_internal_errors($previous);

        if (! $loaded) {
            throw new \RuntimeException('This Word file is damaged or not a real .docx.');
        }

        $body = $doc->getElementsByTagNameNS(self::W, 'body')->item(0);
        if (! $body) {
            return '';
        }

        $lines = [];
        foreach ($body->childNodes as $node) {
            if (! $node instanceof \DOMElement) {
                continue;
            }

            if ($node->localName === 'p') {
                $lines[] = self::paragraph($node);
            } elseif ($node->localName === 'tbl') {
                foreach (self::table($node) as $row) {
                    $lines[] = $row;
                }
            }
        }

        // Collapse runs of blank lines to one: paragraphs separate products.
        $text = implode("\n", $lines);

        return trim(preg_replace("/\n{3,}/", "\n\n", $text) ?? '');
    }

    private static function paragraph(\DOMElement $p): string
    {
        $text = '';

        foreach ($p->getElementsByTagNameNS(self::W, '*') as $el) {
            $text .= match ($el->localName) {
                't' => $el->textContent,
                'tab' => "\t",
                'br', 'cr' => "\n",
                default => '',
            };
        }

        $text = trim($text);
        $listed = $p->getElementsByTagNameNS(self::W, 'numPr')->length > 0;

        return $listed && $text !== '' ? '- '.$text : $text;
    }

    /** @return list<string> */
    private static function table(\DOMElement $table): array
    {
        $rows = [];

        foreach ($table->getElementsByTagNameNS(self::W, 'tr') as $tr) {
            $cells = [];

            foreach ($tr->childNodes as $tc) {
                if (! $tc instanceof \DOMElement || $tc->localName !== 'tc') {
                    continue;
                }

                $parts = [];
                foreach ($tc->getElementsByTagNameNS(self::W, 'p') as $p) {
                    $line = trim(self::paragraph($p), "- \t");
                    if ($line !== '') {
                        $parts[] = $line;
                    }
                }
                $cells[] = implode(' / ', $parts);
            }

            if (trim(implode('', $cells)) !== '') {
                $rows[] = implode(' | ', $cells);
            }
        }

        return $rows;
    }
}
