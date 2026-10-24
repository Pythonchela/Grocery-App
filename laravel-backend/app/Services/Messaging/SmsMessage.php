<?php

namespace App\Services\Messaging;

/**
 * One text to one number, described in both forms providers need: the words
 * (free-text providers) and a template key with variables (DLT providers, where
 * the wording is pre-approved and only the variables change).
 */
final class SmsMessage
{
    public const OTP = 'otp';

    public const ORDER = 'order';

    /**
     * @param  string  $to  the national number as stored, e.g. 9876543210
     * @param  string  $template  OTP or ORDER
     * @param  array<string, string>  $vars  template variables
     */
    public function __construct(
        public readonly string $to,
        public readonly string $text,
        public readonly string $template,
        public readonly array $vars = [],
    ) {}

    public static function otp(string $to, string $otp, string $appName): self
    {
        return new self($to, "Your {$appName} login OTP is {$otp}. Valid for 5 minutes. Do not share it.", self::OTP, ['otp' => $otp]);
    }

    public static function order(string $to, string $message): self
    {
        return new self($to, $message, self::ORDER, ['message' => $message]);
    }
}
