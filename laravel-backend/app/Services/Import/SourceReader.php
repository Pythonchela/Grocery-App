<?php

namespace App\Services\Import;

use App\Services\Import\Documents\DocxReader;
use App\Services\Import\Documents\XlsxReader;
use Illuminate\Http\UploadedFile;

/**
 * Turns whatever the owner uploaded into the two things the importer works with:
 * text (from spreadsheets, Word files, CSV, plain text) and media for the AI to
 * look at (photos and PDFs).
 *
 * Nothing here guesses at meaning. It only opens files; reading products out of
 * them is the importer's job. A file it cannot open becomes a plain-language
 * problem, never an exception, so one bad file does not sink a batch.
 */
class SourceReader
{
    public const TEXT_LIMIT = 400000;

    /** Largest PDF sent to the AI. Requests carry the file inline, which Google caps near 20MB. */
    public const PDF_LIMIT = 12 * 1024 * 1024;

    public const IMAGE_LIMIT = 15 * 1024 * 1024;

    /** The long edge photos are shrunk to before the AI sees them. */
    private const AI_IMAGE_EDGE = 1600;

    private const IMAGES = ['jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp'];

    private const TEXT = ['txt', 'csv', 'tsv', 'md', 'json'];

    /**
     * @param  list<UploadedFile>  $files
     * @return array{
     *   texts: list<array{name: string, text: string, tabular: bool}>,
     *   media: list<array{name: string, kind: string, mime: string, data: string, file: UploadedFile}>,
     *   problems: list<string>,
     *   notes: list<string>
     * }
     */
    public function read(array $files, ?string $pasted = null): array
    {
        $out = ['texts' => [], 'media' => [], 'problems' => [], 'notes' => []];

        if ($pasted !== null && trim($pasted) !== '') {
            $out['texts'][] = ['name' => 'Pasted text', 'text' => self::clip($pasted), 'tabular' => false];
        }

        foreach ($files as $file) {
            $name = $file->getClientOriginalName();
            $ext = strtolower($file->getClientOriginalExtension());

            try {
                $this->readOne($file, $name, $ext, $out);
            } catch (\Throwable $e) {
                $out['problems'][] = "{$name}: ".($e instanceof \RuntimeException ? $e->getMessage() : 'could not be read.');
            }
        }

        return $out;
    }

    private function readOne(UploadedFile $file, string $name, string $ext, array &$out): void
    {
        if (in_array($ext, self::TEXT, true)) {
            $text = self::decode((string) file_get_contents($file->getRealPath()));
            if (trim($text) === '') {
                $out['problems'][] = "{$name}: the file is empty.";

                return;
            }
            $out['texts'][] = ['name' => $name, 'text' => self::clip($text), 'tabular' => in_array($ext, ['csv', 'tsv'], true)];

            return;
        }

        if ($ext === 'xlsx') {
            $read = XlsxReader::read($file->getRealPath());
            if ($read['sheets'] === []) {
                $out['problems'][] = "{$name}: the workbook has no data in it.";

                return;
            }
            if ($read['truncated']) {
                $out['notes'][] = "{$name}: only the first ".XlsxReader::MAX_ROWS.' rows of each sheet were read. Split the file to import the rest.';
            }
            // Each sheet is its own table, so each is read on its own.
            foreach ($read['sheets'] as $sheet) {
                $label = count($read['sheets']) > 1 ? "{$name} ({$sheet['name']})" : $name;
                $out['texts'][] = ['name' => $label, 'text' => self::clip($sheet['text']), 'tabular' => true];
            }

            return;
        }

        if ($ext === 'docx') {
            $text = DocxReader::read($file->getRealPath());
            if (trim($text) === '') {
                $out['problems'][] = "{$name}: no text was found in the document. If it is made of pictures, upload those as photos or save it as a PDF.";

                return;
            }
            $out['texts'][] = ['name' => $name, 'text' => self::clip($text), 'tabular' => false];

            return;
        }

        if ($ext === 'pdf') {
            if ($file->getSize() > self::PDF_LIMIT) {
                $out['problems'][] = "{$name}: the PDF is over 12 MB. Split it into smaller parts.";

                return;
            }
            $out['media'][] = [
                'name' => $name,
                'kind' => 'pdf',
                'mime' => 'application/pdf',
                'data' => base64_encode((string) file_get_contents($file->getRealPath())),
                'file' => $file,
            ];

            return;
        }

        if (isset(self::IMAGES[$ext])) {
            if ($file->getSize() > self::IMAGE_LIMIT) {
                $out['problems'][] = "{$name}: the photo is over 15 MB.";

                return;
            }
            [$mime, $bytes] = self::forAi($file->getRealPath(), self::IMAGES[$ext]);
            $out['media'][] = ['name' => $name, 'kind' => 'image', 'mime' => $mime, 'data' => base64_encode($bytes), 'file' => $file];

            return;
        }

        $out['problems'][] = match ($ext) {
            'xls' => "{$name}: old Excel (.xls) files are not supported. Save it as .xlsx or .csv.",
            'doc' => "{$name}: old Word (.doc) files are not supported. Save it as .docx or PDF.",
            'heic', 'heif' => "{$name}: iPhone HEIC photos are not supported. Share the photo as JPEG, or take it with the 'Most Compatible' camera setting.",
            default => "{$name}: .{$ext} files are not supported. Use a PDF, Word, Excel, CSV, text file or a JPG, PNG or WebP photo.",
        };
    }

    /** UTF-8 text from a file that may have a byte-order mark or be Windows-1252. */
    public static function decode(string $bytes): string
    {
        if (str_starts_with($bytes, "\xEF\xBB\xBF")) {
            $bytes = substr($bytes, 3);
        } elseif (str_starts_with($bytes, "\xFF\xFE") || str_starts_with($bytes, "\xFE\xFF")) {
            return (string) mb_convert_encoding($bytes, 'UTF-8', 'UTF-16');
        }

        return mb_check_encoding($bytes, 'UTF-8') ? $bytes : (string) mb_convert_encoding($bytes, 'UTF-8', 'Windows-1252');
    }

    private static function clip(string $text): string
    {
        return mb_strlen($text) > self::TEXT_LIMIT ? mb_substr($text, 0, self::TEXT_LIMIT) : $text;
    }

    /**
     * A phone photo is several megabytes and the AI reads it just as well at
     * 1600px, so a smaller copy goes over the wire. The original is what gets
     * stored as the product picture.
     *
     * @return array{0: string, 1: string} mime type and bytes
     */
    private static function forAi(string $path, string $mime): array
    {
        $bytes = (string) file_get_contents($path);

        if (! function_exists('imagecreatefromstring') || ! function_exists('getimagesizefromstring')) {
            return [$mime, $bytes];
        }

        $size = @getimagesizefromstring($bytes);
        if (! $size || (max($size[0], $size[1]) <= self::AI_IMAGE_EDGE && strlen($bytes) < 1500000)) {
            return [$mime, $bytes];
        }

        $image = @imagecreatefromstring($bytes);
        if (! $image) {
            return [$mime, $bytes];
        }

        $scale = min(1, self::AI_IMAGE_EDGE / max($size[0], $size[1]));
        $width = max(1, (int) round($size[0] * $scale));
        $height = max(1, (int) round($size[1] * $scale));
        $small = imagecreatetruecolor($width, $height);
        // A transparent PNG goes onto white rather than black.
        imagefill($small, 0, 0, imagecolorallocate($small, 255, 255, 255));
        imagecopyresampled($small, $image, 0, 0, 0, 0, $width, $height, $size[0], $size[1]);

        ob_start();
        imagejpeg($small, null, 85);
        $jpeg = (string) ob_get_clean();

        return $jpeg === '' ? [$mime, $bytes] : ['image/jpeg', $jpeg];
    }
}
