<?php

namespace App\Services\Import;

use App\Models\Category;
use App\Support\MediaUpload;
use Illuminate\Http\UploadedFile;

/**
 * Reads whatever the owner hands over, in whatever form, into rows to review.
 *
 *  - Spreadsheets and CSV with named columns are read directly. That is exact, free
 *    and has no size limit, so the AI is not asked to do what a table already says.
 *  - Everything else (Word, PDF, loose text, a table with unfamiliar headings) and
 *    all photos go to Gemini, which fills the full listing.
 *  - Photos that show a product are saved and attached to it as its pictures.
 *  - The result is checked against the source and the existing catalogue before the
 *    owner sees it. Nothing is created here.
 */
class ProductImporter
{
    public function __construct(
        private SourceReader $reader,
        private AiProductExtractor $ai,
        private ImportRowFactory $factory,
        private ImportVerifier $verifier,
    ) {}

    /**
     * @param  list<UploadedFile>  $files
     * @param  array{default_stock?: int, hint?: string, category_id?: ?string}  $options
     * @return array{rows: list<array>, format: string, driver: string, problems: list<string>, notes: list<string>}
     */
    public function run(array $files, ?string $pasted, array $options = []): array
    {
        $categories = Category::select('id', 'name', 'slug')->get()->map->only(['id', 'name', 'slug'])->all();
        $defaultStock = (int) ($options['default_stock'] ?? 10);
        $sources = $this->reader->read($files, $pasted);

        $problems = $sources['problems'];
        $notes = $sources['notes'];
        $rows = [];
        $drivers = [];
        $formats = [];
        $aiTexts = [];

        // Tables with named columns are read exactly; the rest is for the AI.
        foreach ($sources['texts'] as $text) {
            $table = $this->readTable($text, $categories, $defaultStock);

            if ($table !== null) {
                foreach ($table['rows'] as $row) {
                    $rows[] = $row + ['source' => $text['name']];
                }
                $drivers['table'] = true;
                $formats[$table['format']] = true;
            } else {
                $aiTexts[] = $text;
            }
        }

        $needsAi = $aiTexts !== [] || $sources['media'] !== [];
        $aiMedia = $sources['media'];

        if ($needsAi && ! $this->ai->available()) {
            [$fallbackRows, $fallbackProblems] = $this->withoutAi($aiTexts, $aiMedia, $categories, $defaultStock);
            $rows = array_merge($rows, $fallbackRows);
            $problems = array_merge($problems, $fallbackProblems);
            if ($fallbackRows) {
                $drivers['basic'] = true;
            }
        } elseif ($needsAi) {
            try {
                $found = $this->ai->extract(
                    ['texts' => $aiTexts, 'media' => $aiMedia],
                    ['categories' => $categories, 'hint' => (string) ($options['hint'] ?? '')],
                );
            } catch (GeminiException $e) {
                $problems[] = $e->getMessage();
                $found = ['records' => [], 'notes' => []];
            }

            $notes = array_merge($notes, $found['notes']);
            $aiRows = $this->factory->rows($found['records'], $categories, $defaultStock);
            $aiRows = $this->attachPhotos($aiRows, $aiMedia, $problems);

            $names = array_map(fn ($s) => $s['name'], array_merge($aiTexts, $aiMedia));
            foreach ($aiRows as $row) {
                $rows[] = $row + ['source' => implode(', ', $names)];
            }

            if ($aiRows) {
                $drivers['ai'] = true;
                $formats[$aiMedia ? 'pictures' : 'document'] = true;
            }
        }

        if (! empty($options['category_id'])) {
            $rows = $this->applyCategory($rows, $categories, (string) $options['category_id']);
        }

        $rows = $this->verifier->verify(
            $rows,
            array_map(fn ($t) => $t['text'], $sources['texts']),
            $sources['media'] !== [],
        );

        // Fresh numbering, so the review screen can address each row.
        foreach ($rows as $i => &$row) {
            $row['index'] = $i;
            $row['importable'] = $row['title'] !== '' && $row['price'] !== null && $row['category_id'] !== null;
        }
        unset($row);

        return [
            'rows' => $rows,
            'format' => implode(' + ', array_keys($formats)) ?: 'empty',
            'driver' => implode(' + ', array_keys($drivers)) ?: 'none',
            'problems' => array_values(array_unique($problems)),
            'notes' => array_values(array_unique($notes)),
        ];
    }

    /**
     * Rows from a table whose columns were recognised by name, or null when the
     * text is not that kind of table.
     */
    private function readTable(array $text, array $categories, int $defaultStock): ?array
    {
        $raw = $text['tabular'] ? $this->factory->stripPreamble($text['text']) : $text['text'];
        $result = $this->factory->parse($raw, ['categories' => $categories, 'default_stock' => $defaultStock]);

        if (! $result['structured'] || $result['rows'] === []) {
            return null;
        }

        return ['rows' => $result['rows'], 'format' => $result['format']];
    }

    /** What can be done with no AI key: loose text through the built-in reader; photos and PDFs not at all. */
    private function withoutAi(array $texts, array $media, array $categories, int $defaultStock): array
    {
        $rows = [];
        $problems = [];

        foreach ($texts as $text) {
            $result = $this->factory->parse($text['text'], ['categories' => $categories, 'default_stock' => $defaultStock]);
            foreach ($result['rows'] as $row) {
                $rows[] = $row + ['source' => $text['name']];
            }
        }

        if ($media !== []) {
            $problems[] = 'Photos and PDFs are read by AI. Add a Gemini API key in Settings, then upload them again.';
        }

        return [$rows, $problems];
    }

    /**
     * Saves the photos the AI says show a product, and puts them on that product.
     * Photos that only carried information (a price list page) are not kept.
     *
     * @param  list<array>  $rows
     * @param  list<array>  $media
     */
    private function attachPhotos(array $rows, array $media, array &$problems): array
    {
        $images = [];
        foreach ($media as $i => $m) {
            if ($m['kind'] === 'image') {
                $images[$i + 1] = $m;
            }
        }
        if ($images === []) {
            return $rows;
        }

        // One product and its photos, with nothing said about which is which: they all belong to it.
        $assigned = array_merge(...array_map(fn ($r) => $r['photo_numbers'], $rows) ?: [[]]);
        if (count($rows) === 1 && array_intersect($assigned, array_keys($images)) === []) {
            $rows[0]['photo_numbers'] = array_keys($images);
        }

        $saved = [];
        foreach ($rows as &$row) {
            $row['images'] = $row['images'] ?? [];

            foreach ($row['photo_numbers'] as $number) {
                if (! isset($images[$number])) {
                    continue;
                }

                if (! array_key_exists($number, $saved)) {
                    $saved[$number] = $this->savePhoto($images[$number], $problems);
                }
                if ($saved[$number] !== null) {
                    $row['images'][] = $saved[$number];
                }
            }

            $row['images'] = array_values(array_unique($row['images']));
        }
        unset($row);

        return $rows;
    }

    private function savePhoto(array $media, array &$problems): ?string
    {
        /** @var UploadedFile $file */
        $file = $media['file'];

        // Only a real picture is stored, whatever the file is called.
        if (@getimagesize($file->getRealPath()) === false) {
            $problems[] = "{$media['name']}: this is not a valid picture, so it was not saved.";

            return null;
        }

        try {
            return MediaUpload::store($file);
        } catch (\Throwable $e) {
            report($e);
            $problems[] = "{$media['name']}: the photo could not be saved. Check the storage settings.";

            return null;
        }
    }

    /** The owner chose one category for the whole upload; rows the reader could not place go there. */
    private function applyCategory(array $rows, array $categories, string $categoryId): array
    {
        $known = collect($categories)->firstWhere('id', $categoryId);
        if (! $known) {
            return $rows;
        }

        foreach ($rows as &$row) {
            if ($row['category_id'] === null) {
                $row['category_id'] = $known['id'];
                $row['issues'] = array_values(array_filter(
                    $row['issues'] ?? [],
                    fn ($i) => stripos($i, 'category') === false
                ));
                $row['confidence']['category'] = 0.5;
            }
        }
        unset($row);

        return $rows;
    }
}
