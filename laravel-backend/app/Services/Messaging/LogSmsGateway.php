<?php

namespace App\Services\Messaging;

use Illuminate\Support\Facades\Log;

/**
 * Sends nothing. For development and for a deployment with no SMS provider yet.
 *
 * The text itself is written to the log only in local and testing, where reading an
 * OTP out of the log is how you sign in. Anywhere else it is left out: a log file
 * full of live one-time codes would be a login for anyone who can read it.
 */
class LogSmsGateway implements SmsGateway
{
    public function name(): string
    {
        return 'log';
    }

    public function send(SmsMessage $message): void
    {
        $context = ['to' => '******'.substr($message->to, -4)];

        if (app()->environment(['local', 'testing'])) {
            $context['message'] = $message->text;
        }

        Log::info('[SMS][not sent: no provider configured]', $context);
    }
}
