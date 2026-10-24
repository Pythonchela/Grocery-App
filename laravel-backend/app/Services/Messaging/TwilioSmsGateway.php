<?php

namespace App\Services\Messaging;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/** Twilio Programmable Messaging. Free text; the variables of a template are not used. */
class TwilioSmsGateway implements SmsGateway
{
    /**
     * @param  array{sid?: ?string, token?: ?string, from?: ?string}  $config
     */
    public function __construct(private readonly array $config, private readonly string $countryCode = '91') {}

    public function name(): string
    {
        return 'twilio';
    }

    public function send(SmsMessage $message): void
    {
        $sid = (string) ($this->config['sid'] ?? '');
        $token = (string) ($this->config['token'] ?? '');
        $from = (string) ($this->config['from'] ?? '');

        if ($sid === '' || $token === '' || $from === '') {
            throw new SmsDeliveryException('Twilio is not set up: the account SID, token and sender are all needed.');
        }

        // The account SID goes into the URL path, so it is held to its real shape
        // rather than trusted.
        if (! preg_match('/^AC[0-9a-f]{32}$/i', $sid)) {
            throw new SmsDeliveryException('That does not look like a Twilio account SID.');
        }

        $body = ['To' => '+'.$this->countryCode.$message->to, 'Body' => $message->text];
        $body[str_starts_with($from, 'MG') ? 'MessagingServiceSid' : 'From'] = $from;

        try {
            $response = Http::timeout(8)
                ->asForm()
                ->withBasicAuth($sid, $token)
                ->post("https://api.twilio.com/2010-04-01/Accounts/{$sid}/Messages.json", $body);
        } catch (ConnectionException) {
            throw new SmsDeliveryException('Could not reach Twilio.');
        }

        if (! $response->successful()) {
            Log::warning('[SMS][twilio] not accepted', ['status' => $response->status(), 'code' => $response->json('code')]);

            throw new SmsDeliveryException(
                in_array($response->status(), [401, 403], true)
                    ? 'Twilio rejected the account SID or token.'
                    : 'Twilio did not accept the message.'
            );
        }
    }
}
