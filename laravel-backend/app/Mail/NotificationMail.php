<?php

namespace App\Mail;

use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

/**
 * The email form of an in-app notification: the same title and body, in a plain
 * branded wrapper. One template for every kind keeps what customers receive
 * consistent with what the bell shows.
 */
class NotificationMail extends Mailable
{
    public function __construct(
        public readonly string $headline,
        public readonly ?string $body = null,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: $this->headline);
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.notification',
            text: 'emails.notification-text',
            with: [
                'appName' => config('app.name'),
                'storeUrl' => rtrim((string) config('messaging.store_url'), '/'),
            ],
        );
    }
}
