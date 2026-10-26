<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Default Filesystem Disk
    |--------------------------------------------------------------------------
    |
    | Here you may specify the default filesystem disk that should be used
    | by the framework. The "local" disk, as well as a variety of cloud
    | based disks are available to your application for file storage.
    |
    */

    'default' => env('FILESYSTEM_DISK', 'local'),

    /*
    |--------------------------------------------------------------------------
    | Filesystem Disks
    |--------------------------------------------------------------------------
    |
    | Below you may configure as many filesystem disks as necessary, and you
    | may even configure multiple disks for the same driver. Examples for
    | most supported storage drivers are configured here for reference.
    |
    | Supported drivers: "local", "ftp", "sftp", "s3"
    |
    */

    'disks' => [

        'local' => [
            'driver' => 'local',
            'root' => storage_path('app/private'),
            'serve' => true,
            'throw' => false,
            'report' => false,
        ],

        'public' => [
            'driver' => 'local',
            'root' => storage_path('app/public'),
            'url' => rtrim(env('APP_URL', 'http://localhost'), '/').'/storage',
            'visibility' => 'public',
            'throw' => false,
            'report' => false,
        ],

        /*
        | The disk the app writes uploaded files to. It is the server's own disk
        | until S3 is chosen (Admin -> Integrations -> Image & file storage, or
        | STORAGE_DRIVER=s3 here), so nothing changes for an existing install.
        |
        |   media - product images and other public uploads. Needs a bucket that
        |           allows public reads.
        |
        | No `visibility` on the S3 form: buckets created since 2023 reject the
        | public-read ACL it would request. Public reads come from the bucket's policy
        | or a CDN. (IntegrationSettings::derive() keeps this consistent when the
        | admin panel switches the driver.)
        */
        'media' => [
            'driver' => env('STORAGE_DRIVER', 'local'),
            'root' => storage_path('app/public'),
            // `public_url` is the bucket's public address as configured (empty until set);
            // `url` is what Storage::url() uses, and follows the driver.
            'public_url' => env('AWS_URL'),
            'url' => env('STORAGE_DRIVER', 'local') === 's3'
                ? env('AWS_URL')
                : rtrim(env('APP_URL', 'http://localhost'), '/').'/storage',
            'visibility' => env('STORAGE_DRIVER', 'local') === 's3' ? null : 'public',
            'key' => env('AWS_ACCESS_KEY_ID'),
            'secret' => env('AWS_SECRET_ACCESS_KEY'),
            'region' => env('AWS_DEFAULT_REGION'),
            'bucket' => env('AWS_BUCKET'),
            'endpoint' => env('AWS_ENDPOINT'),
            'use_path_style_endpoint' => filled(env('AWS_ENDPOINT')),
            'http' => ['connect_timeout' => 5, 'timeout' => 30],
            // Fail loudly: a silent `false` from a failed upload was once stored as a path.
            'throw' => true,
            'report' => false,
        ],

        's3' => [
            'driver' => 's3',
            'key' => env('AWS_ACCESS_KEY_ID'),
            'secret' => env('AWS_SECRET_ACCESS_KEY'),
            'region' => env('AWS_DEFAULT_REGION'),
            'bucket' => env('AWS_BUCKET'),
            'url' => env('AWS_URL'),
            'endpoint' => env('AWS_ENDPOINT'),
            'use_path_style_endpoint' => env('AWS_USE_PATH_STYLE_ENDPOINT', false),
            'throw' => false,
            'report' => false,
        ],

    ],

    /*
    |--------------------------------------------------------------------------
    | Symbolic Links
    |--------------------------------------------------------------------------
    |
    | Here you may configure the symbolic links that will be created when the
    | `storage:link` Artisan command is executed. The array keys should be
    | the locations of the links and the values should be their targets.
    |
    */

    'links' => [
        public_path('storage') => storage_path('app/public'),
    ],

];
