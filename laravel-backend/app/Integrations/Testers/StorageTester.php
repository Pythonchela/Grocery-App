<?php

namespace App\Integrations\Testers;

use App\Integrations\HostGuard;
use Aws\S3\Exception\S3Exception;
use Illuminate\Contracts\Filesystem\Filesystem;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Throwable;

/**
 * Proves the buckets work before anything depends on them: writes a small file,
 * reads it back and removes it, in both buckets. For the public bucket it also
 * fetches the file over the Public URL - a bucket that accepts uploads but is not
 * publicly readable is the classic "images upload fine and then never show".
 *
 * The test disks are built here from the values in the form, so credentials that
 * have not been saved are tried without touching the live configuration.
 */
class StorageTester implements Tester
{
    public function test(array $values, ?string $target = null): TestResult
    {
        if (($values['driver'] ?? 'local') !== 's3') {
            return TestResult::unavailable('Files are kept on the server disk. Choose S3 to use a bucket.');
        }

        foreach (['bucket', 'private_bucket', 'public_url', 'region', 'access_key', 'secret_key'] as $needed) {
            if (blank($values[$needed] ?? null)) {
                return TestResult::incomplete('Fill in every storage setting (the endpoint may stay empty for Amazon S3) to test.');
            }
        }

        if (($values['bucket'] ?? null) === ($values['private_bucket'] ?? null)) {
            return TestResult::failed('The public and private buckets must be different. Seller documents must never share a bucket that allows public reads.');
        }

        $endpoint = (string) ($values['endpoint'] ?? '');

        if ($endpoint !== '' && ($problem = HostGuard::problem((string) parse_url($endpoint, PHP_URL_HOST))) !== null) {
            return TestResult::failed($problem);
        }

        $probe = 'healthcheck/'.Str::random(24).'.txt';
        $body = Str::random(32);

        try {
            $public = $this->disk($values, (string) $values['bucket']);
            $private = $this->disk($values, (string) $values['private_bucket']);

            $this->roundTrip($private, $probe, $body, null);

            $publicUrl = rtrim((string) $values['public_url'], '/').'/'.$probe;
            $readable = $this->roundTrip($public, $probe, $body, $publicUrl);
        } catch (S3Exception $e) {
            return TestResult::failed($this->explainS3($e));
        } catch (Throwable) {
            return TestResult::failed('Could not reach the storage service. Check the endpoint, region and that your network allows it.');
        }

        if ($readable !== true) {
            return TestResult::failed($readable);
        }

        return TestResult::ok('Both buckets accept uploads, and files in the public bucket are readable at the Public URL.');
    }

    /** @param  array<string, mixed>  $values */
    private function disk(array $values, string $bucket): Filesystem
    {
        $endpoint = (string) ($values['endpoint'] ?? '');

        return Storage::build([
            'driver' => 's3',
            'key' => $values['access_key'],
            'secret' => $values['secret_key'],
            'region' => $values['region'],
            'bucket' => $bucket,
            'endpoint' => $endpoint !== '' ? $endpoint : null,
            'use_path_style_endpoint' => $endpoint !== '',
            'throw' => true,
            'http' => ['connect_timeout' => 5, 'timeout' => 12],
        ]);
    }

    /**
     * Write, read back, (optionally) fetch publicly, delete. Always deletes.
     *
     * @return true|string true when everything held, else what was wrong
     */
    private function roundTrip(Filesystem $disk, string $path, string $body, ?string $publicUrl): bool|string
    {
        $disk->put($path, $body);

        try {
            if ($disk->get($path) !== $body) {
                return 'The bucket returned different content from what was written.';
            }

            if ($publicUrl !== null) {
                $host = (string) parse_url($publicUrl, PHP_URL_HOST);

                if (($problem = HostGuard::problem($host)) !== null) {
                    return 'The Public URL: '.$problem;
                }

                $response = Http::timeout(8)->withoutRedirecting()->get($publicUrl);

                if (! $response->successful() || $response->body() !== $body) {
                    return "Uploads work, but the file is not readable at the Public URL (it answered {$response->status()}). "
                        .'Make the public bucket publicly readable, or fix the URL, or images will not show.';
                }
            }

            return true;
        } finally {
            $disk->delete($path);
        }
    }

    private function explainS3(S3Exception $e): string
    {
        return match ($e->getAwsErrorCode()) {
            'InvalidAccessKeyId' => 'The access key ID is not recognised.',
            'SignatureDoesNotMatch' => 'The secret access key is wrong (or the region is).',
            'NoSuchBucket' => 'One of the buckets does not exist. Check the names.',
            'AccessDenied', 'AllAccessDisabled' => 'The key is valid but is not allowed to write to the bucket. Give it read, write and delete access.',
            'AuthorizationHeaderMalformed', 'PermanentRedirect' => 'The region does not match the bucket.',
            default => 'The storage service refused the request'.($e->getAwsErrorCode() ? " ({$e->getAwsErrorCode()})." : '.'),
        };
    }
}
