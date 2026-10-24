<?php

namespace App\Services\Messaging;

/**
 * Carries one text message. Implementations only deliver; they decide nothing
 * about what is sent or to whom.
 */
interface SmsGateway
{
    /** Short name, for logs and the admin screen. */
    public function name(): string;

    /**
     * @throws SmsDeliveryException when the provider did not accept the message.
     *                              The message is safe to show an admin; it never
     *                              contains a credential or the provider's raw reply.
     */
    public function send(SmsMessage $message): void;
}
