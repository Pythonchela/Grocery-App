<?php

namespace App\Integrations\Testers;

use App\Integrations\HostGuard;
use App\Logging\SecretScrubber;
use Symfony\Component\Mailer\Mailer;
use Symfony\Component\Mailer\Transport\Smtp\EsmtpTransport;
use Symfony\Component\Mime\Address;
use Symfony\Component\Mime\Email;
use Throwable;

/**
 * Sends one real email through the SMTP server as configured (saved or as typed),
 * to the admin who asked. The mail goes through a transport built here, so values
 * that have not been saved are tried without touching the live mailer.
 *
 * The recipient is always the signed-in admin's own address, never an input: this
 * must not become a way to send mail to arbitrary people from the store's domain.
 */
class EmailTester implements Tester
{
    public function test(array $values, ?string $target = null): TestResult
    {
        if (($values['mailer'] ?? 'log') !== 'smtp') {
            return TestResult::unavailable('The mailer is set to Log, so nothing is sent. Choose SMTP to send real email.');
        }

        $host = trim((string) ($values['smtp_host'] ?? ''));
        $port = (int) ($values['smtp_port'] ?? 0);
        $from = trim((string) ($values['from_address'] ?? ''));

        if ($host === '' || $port < 1 || $from === '') {
            return TestResult::incomplete('Enter the SMTP host, port and from address to test.');
        }

        if (! filter_var($target, FILTER_VALIDATE_EMAIL)) {
            return TestResult::incomplete('Your admin account has no email address to send the test to.');
        }

        if (($problem = HostGuard::problem($host)) !== null) {
            return TestResult::failed($problem);
        }

        $username = (string) ($values['smtp_username'] ?? '');
        $password = (string) ($values['smtp_password'] ?? '');

        try {
            // Connect to the address that was just checked, not whatever the name
            // resolves to a moment later, and verify the certificate for the name.
            $pinned = config('integrations.allow_private_hosts') ? $host : (HostGuard::resolve($host)[0] ?? $host);

            $transport = new EsmtpTransport($pinned, $port, $port === 465 ? true : null);
            $transport->getStream()->setTimeout(8);
            $transport->getStream()->setStreamOptions(['ssl' => ['peer_name' => $host]]);

            if ($username !== '') {
                $transport->setUsername($username)->setPassword($password);
            }

            $appName = (string) config('app.name');

            (new Mailer($transport))->send(
                (new Email)
                    ->from(new Address($from, (string) ($values['from_name'] ?? $appName)))
                    ->to($target)
                    ->subject("Test email from {$appName}")
                    ->text("This is a test message from {$appName}. Your email settings work."),
            );
        } catch (Throwable $e) {
            return TestResult::failed($this->explain($e, [$password, $username]));
        }

        return TestResult::ok("A test email was sent to {$target}. Check that it arrives, and is not in spam.");
    }

    /**
     * The mail server's own words are the useful part of a failure ("535 bad
     * credentials", "sender not verified"), so they are shown, trimmed, with
     * anything secret removed.
     *
     * @param  list<string>  $secrets
     */
    private function explain(Throwable $e, array $secrets): string
    {
        $message = SecretScrubber::scrub($e->getMessage());

        foreach ($secrets as $secret) {
            if ($secret !== '') {
                $message = str_replace($secret, SecretScrubber::MASK, $message);
            }
        }

        $message = trim(preg_replace('/\s+/', ' ', $message) ?? '');

        return 'The mail server did not accept the test: '.mb_substr($message !== '' ? $message : 'connection failed', 0, 180);
    }
}
