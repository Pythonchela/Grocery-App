<?php

namespace App\Services\Messaging;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * MSG91 Flow API. Indian carriers only deliver pre-approved (DLT) wording, so this
 * does not send free text: it names an approved template and fills its variables.
 * A message kind with no template configured is refused, not sent as something else.
 */
class Msg91SmsGateway implements SmsGateway
{
    // Fixed. Never built from input.
    private const ENDPOINT = 'https://control.msg91.com/api/v5/flow';

    /**
     * @param  array{authkey?: ?string, template_otp?: ?string, template_order?: ?string}  $config
     */
    public function __construct(private readonly array $config, private readonly string $countryCode = '91') {}

    public function name(): string
    {
        return 'msg91';
    }

    public function send(SmsMessage $message): void
    {
        $authkey = (string) ($this->config['authkey'] ?? '');
        $templateId = (string) ($message->template === SmsMessage::OTP
            ? ($this->config['template_otp'] ?? '')
            : ($this->config['template_order'] ?? ''));

        if ($authkey === '') {
            throw new SmsDeliveryException('MSG91 is not set up: the auth key is missing.');
        }

        if ($templateId === '') {
            throw new SmsDeliveryException("MSG91 has no approved template for '{$message->template}' messages.");
        }

        try {
            $response = Http::timeout(8)
                ->withHeaders(['authkey' => $authkey, 'accept' => 'application/json'])
                ->asJson()
                ->post(self::ENDPOINT, [
                    'template_id' => $templateId,
                    'short_url' => '0',
                    'recipients' => [array_merge(['mobiles' => $this->countryCode.$message->to], $message->vars)],
                ]);
        } catch (ConnectionException) {
            throw new SmsDeliveryException('Could not reach MSG91.');
        }

        // MSG91 answers 200 even for some failures and says so in `type`.
        if (! $response->successful() || $response->json('type') !== 'success') {
            // Status only. The body can echo the request, including the number.
            Log::warning('[SMS][msg91] not accepted', ['status' => $response->status(), 'type' => $response->json('type')]);

            throw new SmsDeliveryException(
                in_array($response->status(), [401, 403], true)
                    ? 'MSG91 rejected the auth key.'
                    : 'MSG91 did not accept the message.'
            );
        }
    }
}
