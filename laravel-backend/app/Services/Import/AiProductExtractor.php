<?php

namespace App\Services\Import;

/**
 * Reads products out of text, photos and PDFs with Gemini.
 *
 * The model only supplies the extraction. What it returns is treated as a draft:
 * the importer checks the numbers against the source, matches categories against
 * the real list, and the owner reviews every row before anything is created.
 */
class AiProductExtractor
{
    /** Text sent per call. Longer sources are read in several passes. */
    private const CHUNK_CHARS = 40000;

    /** Calls one request may make. The rest is reported, not silently dropped. */
    private const MAX_CALLS = 6;

    public function __construct(private GeminiClient $client) {}

    public function available(): bool
    {
        return $this->client->configured();
    }

    /**
     * @param  array  $sources  the result of SourceReader::read()
     * @param  array  $context  ['categories' => [...], 'hint' => string]
     * @return array{records: list<array>, notes: list<string>}
     *
     * @throws GeminiException
     */
    public function extract(array $sources, array $context = []): array
    {
        $chunks = [];
        foreach ($sources['texts'] as $text) {
            foreach (self::split($text['text']) as $i => $piece) {
                $chunks[] = "FILE: {$text['name']}".($i > 0 ? ' (continued)' : '')."\n".$piece;
            }
        }

        // Photos and PDFs ride on the first call; further calls carry only text.
        $media = $sources['media'];
        $calls = $chunks === [] ? [[]] : array_map(fn ($c) => [$c], $chunks);

        $notes = [];
        if (count($calls) > self::MAX_CALLS) {
            $notes[] = 'This file is long, so only the first part was read. Split it and import the rest separately.';
            $calls = array_slice($calls, 0, self::MAX_CALLS);
        }

        $system = self::instructions($context['categories'] ?? [], (string) ($context['hint'] ?? ''));
        $records = [];

        foreach ($calls as $n => $texts) {
            $parts = [];

            if ($n === 0) {
                foreach ($media as $i => $m) {
                    $parts[] = ['text' => ($m['kind'] === 'pdf' ? 'PDF' : 'Photo').' '.($i + 1).": {$m['name']}"];
                    $parts[] = ['inline_data' => ['mime_type' => $m['mime'], 'data' => $m['data']]];
                }
            }

            foreach ($texts as $text) {
                $parts[] = ['text' => $text];
            }

            if ($parts === []) {
                continue;
            }

            $parts[] = ['text' => 'Extract every product from the material above.'];

            $answer = $this->client->json($parts, self::schema(), $system);

            foreach ((array) ($answer['products'] ?? []) as $product) {
                if (is_array($product)) {
                    $records[] = $product;
                }
            }
            if (! empty($answer['document_notes']) && is_string($answer['document_notes'])) {
                $notes[] = trim($answer['document_notes']);
            }
        }

        return ['records' => $records, 'notes' => array_values(array_unique($notes))];
    }

    /** Splits on blank lines (or lines) so a product is not cut in half. */
    public static function split(string $text, int $limit = self::CHUNK_CHARS): array
    {
        if (mb_strlen($text) <= $limit) {
            return [$text];
        }

        $pieces = [];
        $current = '';

        foreach (preg_split('/(?<=\n)/', $text) as $line) {
            if ($current !== '' && mb_strlen($current) + mb_strlen($line) > $limit) {
                $pieces[] = $current;
                $current = '';
            }
            $current .= $line;
        }

        if ($current !== '') {
            $pieces[] = $current;
        }

        return $pieces;
    }

    public static function instructions(array $categories, string $hint): string
    {
        $names = implode('; ', array_map(fn ($c) => $c['name'], $categories)) ?: '(none yet)';
        $hint = trim($hint) !== '' ? "\nThe owner added this note for the whole upload: ".trim($hint)."\n" : '';

        return <<<TXT
        You read product material for an Indian online shop and fill in a product listing for each product.
        The material may be a price list, a catalogue, a spreadsheet, a Word or PDF document, a handwritten list,
        a screenshot, or photographs of the products themselves.

        Accuracy comes first. A wrong price or a made-up detail costs the owner money, so:
        - Use only what is written in the material or plainly visible in a photograph. Never invent a price, MRP,
          stock figure, weight, brand, material, size or specification. Leave a field out when it is not there.
        - price is the selling price the customer pays; mrp is the higher printed list price. If only one price
          is given, put it in price and leave mrp out. If a photograph has no price tag or label, leave price out.
        - Numbers are plain digits: 3499, not "Rs. 3,499/-". Prices are in rupees. Weights go in grams
          (1.5 kg is 1500), sizes in centimetres. Read Indian number styles correctly (1,25,000 is 125000).
        - One product is one thing a customer buys. Several colours or sizes of the same product are variants of
          one product, not separate products. A set sold together is one product.
        - Give variants only for colours or sizes actually listed. If stock is stated per variant, keep it.
        - category must be exactly one of these names, or left out if none fits: {$names}.
        - Keep the title as a shopper would search for it: brand, product type and key detail, in normal capitalisation.
        - description: use the material's own wording when it has any. When it has none, you may write two or three
          plain sentences from the facts you can see or read (set description_written_by_ai true). Never add claims.
        - features are short bullet points taken from the material. specifications are label and value pairs
          (fabric, fit, warranty, capacity, ingredients, dimensions), grouped under a short heading such as General.
        - manufacturer fields only when the material states them (country of origin, manufacturer, packer).
        - photo_numbers lists the photographs (by their Photo number) that show this product itself. Do not list a
          photograph of a price list, catalogue page or document. Several photos of one product all go on that product.
        - unsure lists the names of fields you were not certain about (blurry text, ambiguous column, guessed match).
        - notes: one short sentence about anything the owner should check on this product.
        - If the material has no products, return an empty products list and say why in document_notes.
        {$hint}
        TXT;
    }

    public static function schema(): array
    {
        $string = ['type' => 'STRING'];
        $list = fn (array $items) => ['type' => 'ARRAY', 'items' => $items];

        $variant = ['type' => 'OBJECT', 'properties' => [
            'color' => $string, 'size' => $string, 'sku' => $string,
            'stock' => ['type' => 'INTEGER'], 'price' => ['type' => 'NUMBER'], 'mrp' => ['type' => 'NUMBER'],
        ]];

        $manufacturer = ['type' => 'OBJECT', 'properties' => [
            'generic_name' => $string, 'country_of_origin' => $string, 'manufacturer_name' => $string,
            'manufacturer_address' => $string, 'packer_name' => $string, 'packer_address' => $string,
        ]];

        $specGroup = ['type' => 'OBJECT', 'properties' => [
            'title' => $string,
            'rows' => $list(['type' => 'OBJECT', 'properties' => ['label' => $string, 'value' => $string]]),
        ]];

        $product = ['type' => 'OBJECT', 'properties' => [
            'title' => $string,
            'brand' => $string,
            'category' => $string,
            'description' => $string,
            'description_written_by_ai' => ['type' => 'BOOLEAN'],
            'features' => $list($string),
            'specifications' => $list($specGroup),
            'manufacturer' => $manufacturer,
            'tags' => $list($string),
            'price' => ['type' => 'NUMBER'],
            'mrp' => ['type' => 'NUMBER'],
            'sku' => $string,
            'stock' => ['type' => 'INTEGER'],
            'weight_grams' => ['type' => 'INTEGER'],
            'length_cm' => ['type' => 'INTEGER'],
            'width_cm' => ['type' => 'INTEGER'],
            'height_cm' => ['type' => 'INTEGER'],
            'variants' => $list($variant),
            'photo_numbers' => $list(['type' => 'INTEGER']),
            'unsure' => $list($string),
            'notes' => $string,
        ], 'required' => ['title']];

        return ['type' => 'OBJECT', 'properties' => [
            'products' => $list($product),
            'document_notes' => $string,
        ], 'required' => ['products']];
    }
}
