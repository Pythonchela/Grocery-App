<?php

namespace App\Services\Import;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * The one place that talks to Gemini for catalogue work: text, photos and PDFs in,
 * structured JSON out.
 *
 * Google retires model names every few months, so the model is never written into
 * the code. It is `services.gemini.model` when the owner sets one, otherwise the
 * newest plain "flash" model the key can see (looked up once and remembered for a
 * day), otherwise the `gemini-flash-latest` alias.
 *
 * The key travels in a header, never the URL: a failed request's exception message
 * includes its URL, which would put the key in the logs.
 */
class GeminiClient
{
    private const BASE = 'https://generativelanguage.googleapis.com/v1beta';

    public function __construct(private ?string $key = null)
    {
        $configured = config('services.gemini.key');
        $this->key ??= is_string($configured) && trim($configured) !== '' ? trim($configured) : null;
    }

    public function configured(): bool
    {
        return $this->key !== null;
    }

    /** The model to call. */
    public function model(): string
    {
        $chosen = config('services.gemini.model');
        if (is_string($chosen) && trim($chosen) !== '') {
            return trim($chosen);
        }

        return Cache::remember('gemini.model.'.sha1((string) $this->key), now()->addDay(), function () {
            try {
                $response = Http::timeout(10)->withHeaders(['x-goog-api-key' => $this->key])
                    ->get(self::BASE.'/models', ['pageSize' => 200]);

                if ($response->successful()) {
                    $found = self::newestFlash((array) $response->json('models', []));
                    if ($found !== null) {
                        return $found;
                    }
                }
            } catch (\Throwable $e) {
                Log::info('[GeminiClient] model lookup failed: '.$e->getMessage());
            }

            return 'gemini-flash-latest';
        });
    }

    /**
     * The highest-numbered plain flash model that can generate content, from the
     * list Google returns. Previews, "lite", image, audio and tuned variants are
     * skipped: the extraction wants the steady general model.
     */
    public static function newestFlash(array $models): ?string
    {
        $best = null;
        $bestVersion = -1.0;

        foreach ($models as $m) {
            $name = preg_replace('#^models/#', '', (string) ($m['name'] ?? ''));
            $methods = (array) ($m['supportedGenerationMethods'] ?? []);

            if (! in_array('generateContent', $methods, true)) {
                continue;
            }
            if (! preg_match('/^gemini-(\d+(?:\.\d+)?)-flash$/', $name, $hit)) {
                continue;
            }

            $version = (float) $hit[1];
            if ($version > $bestVersion) {
                $bestVersion = $version;
                $best = $name;
            }
        }

        return $best;
    }

    /**
     * Ask for JSON that fits $schema.
     *
     * @param  array  $parts   Gemini parts: ['text' => ...] or ['inline_data' => ['mime_type', 'data']]
     * @param  array  $schema  OpenAPI-subset schema for the answer
     * @return array  The decoded answer
     *
     * @throws GeminiException with a message that is safe to show the owner
     */
    public function json(array $parts, array $schema, string $system, int $timeout = 90): array
    {
        if (! $this->configured()) {
            throw new GeminiException('Add a Gemini API key in Settings to read photos and PDFs with AI.');
        }

        $body = [
            'systemInstruction' => ['parts' => [['text' => $system]]],
            'contents' => [['role' => 'user', 'parts' => $parts]],
            'generationConfig' => [
                'temperature' => 0,
                'responseMimeType' => 'application/json',
                'responseSchema' => $schema,
                'maxOutputTokens' => 32000,
            ],
        ];

        $response = null;

        for ($attempt = 1; $attempt <= 2; $attempt++) {
            try {
                $response = Http::timeout($timeout)
                    ->withHeaders(['x-goog-api-key' => $this->key])
                    ->post(self::BASE.'/models/'.$this->model().':generateContent', $body);
            } catch (\Throwable $e) {
                Log::warning('[GeminiClient] request failed: '.$e->getMessage());
                throw new GeminiException('Could not reach Google AI. Check the connection and try again.');
            }

            // A busy or rate-limited moment is worth one more try; anything else is not.
            if (in_array($response->status(), [429, 500, 502, 503, 504], true) && $attempt === 1) {
                sleep(2);
                continue;
            }

            break;
        }

        if (! $response->successful()) {
            // A model name that has since been retired: forget it so the next call looks again.
            if ($response->status() === 404) {
                Cache::forget('gemini.model.'.sha1((string) $this->key));
            }

            throw new GeminiException(match (true) {
                in_array($response->status(), [400, 403], true) && str_contains(strtolower((string) $response->body()), 'api key')
                    => 'Google rejected the Gemini API key. Check it in Settings.',
                $response->status() === 429 => 'Google AI is busy or the free quota is used up. Try again in a minute.',
                $response->status() === 404 => 'The AI model was not found. Try again; it will pick the current one.',
                default => 'Google AI could not read this right now (error '.$response->status().').',
            });
        }

        $blocked = $response->json('promptFeedback.blockReason');
        if ($blocked) {
            throw new GeminiException('Google AI declined to read this file ('.strtolower((string) $blocked).').');
        }

        $text = (string) $response->json('candidates.0.content.parts.0.text', '');
        $decoded = json_decode(trim(str_replace(['```json', '```'], '', $text)), true);

        if (! is_array($decoded)) {
            throw new GeminiException('The AI answered in a form that could not be used. Try again, or split the file into smaller parts.');
        }

        return $decoded;
    }
}
